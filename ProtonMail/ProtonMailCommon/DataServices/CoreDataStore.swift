//
//  CoreDataStoreService.swift
//  ProtonMail - Created on 12/19/18.
//
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of ProtonMail.
//
//  ProtonMail is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ProtonMail is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ProtonMail.  If not, see <https://www.gnu.org/licenses/>.

import Foundation
import CoreData

/// Provide the local store for core data.
/// Inital does nothing extra
class CoreDataStore {
    /// TODO::fixme tempary.
    static let shared = CoreDataStore()

    class var dbUrl: URL {
        return FileManager.default.appGroupsDirectoryURL.appendingPathComponent("ProtonMail.sqlite")
    }

    class var tempUrl: URL {
        return FileManager.default.temporaryDirectoryUrl.appendingPathComponent("ProtonMail.sqlite")
    }

    class var modelBundle: Bundle {
        return Bundle(url: Bundle.main.url(forResource: "ProtonMail", withExtension: "momd")!)!
    }

    static let name: String = "ProtonMail.sqlite"

    lazy var defaultContainer: NSPersistentContainer = { [unowned self] in
        return self.newPersistentContainer(self.managedObjectModel, name: CoreDataStore.name, url: CoreDataStore.dbUrl)
    }()

    lazy var memoryPersistentContainer: NSPersistentContainer = { [unowned self] in
        return self.newMemoryPersistentContainer(self.managedObjectModel, name: CoreDataStore.name)
    }()

    lazy var testPersistentContainer: NSPersistentContainer = { [unowned self] in
        return self.newPersistentContainer(self.managedObjectModel, name: CoreDataStore.name, url: CoreDataStore.tempUrl)
    }()

    lazy var defaultPersistentStore: NSPersistentStoreCoordinator! = { [unowned self] in
        return self.newPersistentStoreCoordinator(self.managedObjectModel, url: CoreDataStore.dbUrl)
    }()

    lazy var memoryPersistentStore: NSPersistentStoreCoordinator! = { [unowned self] in
        return self.newMemoryStoreCoordinator(self.managedObjectModel)
    }()

    lazy var testPersistentStore: NSPersistentStoreCoordinator! = { [unowned self] in
        return self.newPersistentStoreCoordinator(self.managedObjectModel, url: CoreDataStore.tempUrl)
    }()

    private lazy var managedObjectModel: NSManagedObjectModel = { [unowned self] in
        var modelURL = Bundle.main.url(forResource: "ProtonMail", withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: modelURL)!
    }()

    private func newPersistentContainer(_ managedObjectModel: NSManagedObjectModel, name: String, url: URL) -> NSPersistentContainer {
        var url = url
        let container = NSPersistentContainer(name: name, managedObjectModel: managedObjectModel)

        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { (persistentStoreDescription, error) in
            if let _ = error as NSError? {
                container.loadPersistentStores { (_, error) in
                    if let ex = error as NSError? {
                        do {
                            try FileManager.default.removeItem(at: url)
                            LastUpdatedStore.clear()
                        } catch let error as NSError {
                            self.popError(error)
                        }

                        self.popError(ex)
                        fatalError()
                    }
                }
            } else {
                url.excludeFromBackup()
                container.viewContext.automaticallyMergesChangesFromParent = true
                container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            }
        }
        return container
    }

    private func newMemoryPersistentContainer(_ managedObjectModel: NSManagedObjectModel, name: String) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: name, managedObjectModel: managedObjectModel)
        let description = NSPersistentStoreDescription()
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { (_, _) in
        }
        return container
    }

    private func newMemoryStoreCoordinator(_ objectModel: NSManagedObjectModel) -> NSPersistentStoreCoordinator? {
        let coordinator: NSPersistentStoreCoordinator? = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        // Coordinator with in-mem store type
        do {
            try coordinator?.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        } catch {
        }
        return coordinator
    }

    private func newPersistentStoreCoordinator(_ managedObjectModel: NSManagedObjectModel, url: URL) -> NSPersistentStoreCoordinator? {
        var coordinator: NSPersistentStoreCoordinator? = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        var url = url
        do {
            let options: [AnyHashable: Any] = [
                NSInferMappingModelAutomaticallyOption: NSNumber(booleanLiteral: true)
            ]
            try coordinator?.addPersistentStore(ofType: NSSQLiteStoreType,
                                                configurationName: nil,
                                                at: url,
                                                options: options)
            url.excludeFromBackup()
        } catch let ex as NSError {
            if ex.domain == "NSCocoaErrorDomain" && ex.code == 134100 {
                do {
                    try FileManager.default.removeItem(at: url)
                    coordinator = newPersistentStoreCoordinator(managedObjectModel, url: url)
                } catch let error as NSError {
                    coordinator = nil
                    popError(error)
                }
            } else {
                coordinator = nil
                popError(ex)
            }
        }
        return coordinator
    }

    func popError (_ error: NSError) {
        // Report any error we got.
        var dict = [AnyHashable: Any]()
        dict[NSLocalizedDescriptionKey] = LocalString._error_core_data_save_failed
        dict[NSLocalizedFailureReasonErrorKey] = LocalString._error_core_data_load_failed
        dict[NSUnderlyingErrorKey] = error
        // TODO:: need monitor
        let CoreDataServiceErrorDomain = NSError.protonMailErrorDomain("CoreDataService")
        _ = NSError(domain: CoreDataServiceErrorDomain, code: 9999, userInfo: dict as [AnyHashable: Any] as? [String: Any])

        assert(false, "Unresolved error \(error), \(error.userInfo)")
    }

    func cleanLegacy() {
        // the old code data file
        let url = FileManager.default.applicationSupportDirectoryURL.appendingPathComponent("ProtonMail.sqlite")
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
        }
    }
}
