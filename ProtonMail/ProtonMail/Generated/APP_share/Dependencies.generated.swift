// Generated using Sourcery 2.0.2 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT

protocol HasAttachmentMetadataStrippingProtocol {
    var attachmentMetadataStripStatusProvider: AttachmentMetadataStrippingProtocol { get }
}

extension GlobalContainer: HasAttachmentMetadataStrippingProtocol {
    var attachmentMetadataStripStatusProvider: AttachmentMetadataStrippingProtocol {
        attachmentMetadataStripStatusProviderFactory()
    }
}

extension UserContainer: HasAttachmentMetadataStrippingProtocol {
    var attachmentMetadataStripStatusProvider: AttachmentMetadataStrippingProtocol {
        globalContainer.attachmentMetadataStripStatusProvider
    }
}

protocol HasCoreDataContextProviderProtocol {
    var contextProvider: CoreDataContextProviderProtocol { get }
}

extension GlobalContainer: HasCoreDataContextProviderProtocol {
    var contextProvider: CoreDataContextProviderProtocol {
        contextProviderFactory()
    }
}

extension UserContainer: HasCoreDataContextProviderProtocol {
    var contextProvider: CoreDataContextProviderProtocol {
        globalContainer.contextProvider
    }
}

protocol HasFeatureFlagCache {
    var featureFlagCache: FeatureFlagCache { get }
}

extension GlobalContainer: HasFeatureFlagCache {
    var featureFlagCache: FeatureFlagCache {
        featureFlagCacheFactory()
    }
}

extension UserContainer: HasFeatureFlagCache {
    var featureFlagCache: FeatureFlagCache {
        globalContainer.featureFlagCache
    }
}

protocol HasInternetConnectionStatusProviderProtocol {
    var internetConnectionStatusProvider: InternetConnectionStatusProviderProtocol { get }
}

extension GlobalContainer: HasInternetConnectionStatusProviderProtocol {
    var internetConnectionStatusProvider: InternetConnectionStatusProviderProtocol {
        internetConnectionStatusProviderFactory()
    }
}

extension UserContainer: HasInternetConnectionStatusProviderProtocol {
    var internetConnectionStatusProvider: InternetConnectionStatusProviderProtocol {
        globalContainer.internetConnectionStatusProvider
    }
}

protocol HasKeyMakerProtocol {
    var keyMaker: KeyMakerProtocol { get }
}

extension GlobalContainer: HasKeyMakerProtocol {
    var keyMaker: KeyMakerProtocol {
        keyMakerFactory()
    }
}

extension UserContainer: HasKeyMakerProtocol {
    var keyMaker: KeyMakerProtocol {
        globalContainer.keyMaker
    }
}

protocol HasLockCacheStatus {
    var lockCacheStatus: LockCacheStatus { get }
}

extension GlobalContainer: HasLockCacheStatus {
    var lockCacheStatus: LockCacheStatus {
        lockCacheStatusFactory()
    }
}

extension UserContainer: HasLockCacheStatus {
    var lockCacheStatus: LockCacheStatus {
        globalContainer.lockCacheStatus
    }
}

protocol HasQueueManager {
    var queueManager: QueueManager { get }
}

extension GlobalContainer: HasQueueManager {
    var queueManager: QueueManager {
        queueManagerFactory()
    }
}

extension UserContainer: HasQueueManager {
    var queueManager: QueueManager {
        globalContainer.queueManager
    }
}

protocol HasUsersManager {
    var usersManager: UsersManager { get }
}

extension GlobalContainer: HasUsersManager {
    var usersManager: UsersManager {
        usersManagerFactory()
    }
}

extension UserContainer: HasUsersManager {
    var usersManager: UsersManager {
        globalContainer.usersManager
    }
}

protocol HasUserCachedStatus {
    var userCachedStatus: UserCachedStatus { get }
}

extension GlobalContainer: HasUserCachedStatus {
    var userCachedStatus: UserCachedStatus {
        userCachedStatusFactory()
    }
}

extension UserContainer: HasUserCachedStatus {
    var userCachedStatus: UserCachedStatus {
        globalContainer.userCachedStatus
    }
}

protocol HasUserIntroductionProgressProvider {
    var userIntroductionProgressProvider: UserIntroductionProgressProvider { get }
}

extension GlobalContainer: HasUserIntroductionProgressProvider {
    var userIntroductionProgressProvider: UserIntroductionProgressProvider {
        userIntroductionProgressProviderFactory()
    }
}

extension UserContainer: HasUserIntroductionProgressProvider {
    var userIntroductionProgressProvider: UserIntroductionProgressProvider {
        globalContainer.userIntroductionProgressProvider
    }
}

protocol HasComposerViewFactory {
    var composerViewFactory: ComposerViewFactory { get }
}

extension UserContainer: HasComposerViewFactory {
    var composerViewFactory: ComposerViewFactory {
        composerViewFactoryFactory()
    }
}

protocol HasFetchAndVerifyContacts {
    var fetchAndVerifyContacts: FetchAndVerifyContacts { get }
}

extension UserContainer: HasFetchAndVerifyContacts {
    var fetchAndVerifyContacts: FetchAndVerifyContacts {
        fetchAndVerifyContactsFactory()
    }
}

protocol HasFetchAttachment {
    var fetchAttachment: FetchAttachment { get }
}

extension UserContainer: HasFetchAttachment {
    var fetchAttachment: FetchAttachment {
        fetchAttachmentFactory()
    }
}

protocol HasUserManager {
    var user: UserManager { get }
}

extension UserContainer: HasUserManager {
    var user: UserManager {
        userFactory()
    }
}

