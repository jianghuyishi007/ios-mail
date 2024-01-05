// Copyright (c) 2022 Proton Technologies AG
//
// This file is part of Proton Technologies AG and ProtonCore.
//
// ProtonCore is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// ProtonCore is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with ProtonCore. If not, see https://www.gnu.org/licenses/.

public struct AnySpecialLoopFactory<Loop: EventsLoop>: SpecialLoopFactory {

    private let _makeSpecialLoop: (String) -> Loop

    public init<Factory: SpecialLoopFactory>(_ factory: Factory) where Factory.Loop == Loop {
        _makeSpecialLoop = factory.makeSpecialLoop
    }

    // MARK: - SpecialLoopFactory

    public func makeSpecialLoop(forSpecialLoopID specialLoopID: String) -> Loop {
        _makeSpecialLoop(specialLoopID)
    }

}
