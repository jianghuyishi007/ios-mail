// Copyright (c) 2024 Proton Technologies AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Mail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Mail. If not, see https://www.gnu.org/licenses/.

import ProtonCorePayments

final class UpsellTelemetryReporter {
    typealias Dependencies = AnyObject & HasPlanService & HasTelemetryServiceProtocol & HasUserManager

    private unowned let dependencies: Dependencies

    private var plansDataSource: PlansDataSourceProtocol? {
        switch dependencies.planService {
        case .left:
            return nil
        case .right(let pdsp):
            return pdsp
        }
    }

    private var planBeforeUpgrade: String?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func prepare() {
        planBeforeUpgrade = plansDataSource?.currentPlan?.subscriptions.compactMap(\.name).first ?? "free"
    }

    func upsellButtonTapped() async {
        let event = makeEvent(name: .upsellButtonTapped, dimensions: commonDimensions())
        await dependencies.telemetryService.sendEvent(event)
    }

    func upgradeAttempt(protonPlanName: String) async {
        var dimensions = commonDimensions()
        dimensions.selectedPlan = protonPlanName

        let event = makeEvent(name: .upgradeAttempt, dimensions: dimensions)
        await dependencies.telemetryService.sendEvent(event)
    }

    func upgradeSuccess(protonPlanName: String) async {
        var dimensions = commonDimensions()
        dimensions.selectedPlan = protonPlanName

        let event = makeEvent(name: .upgradeSuccess, dimensions: dimensions)
        await dependencies.telemetryService.sendEvent(event)
    }

    private func makeEvent(name: EventName, dimensions: Dimensions) -> TelemetryEvent {
        .init(
            measurementGroup: measurementGroup,
            name: name.rawValue,
            values: [:],
            dimensions: dimensions.asDictionary,
            frequency: .always
        )
    }

    private func commonDimensions() -> Dimensions {
        if !ProcessInfo.isRunningUnitTests {
            assert(planBeforeUpgrade != nil, "current plan name must be stored to accurately report it after the upgrade")
        }

        return .init(
            planBeforeUpgrade: planBeforeUpgrade ?? "unknown",
            daysSinceAccountCreation: accountAgeBracket(),
            upsellModalVersion: upsellModalVersion,
            selectedPlan: nil
        )
    }

    private func accountAgeBracket() -> String {
        let accountCreationDate = Date(timeIntervalSince1970: TimeInterval(dependencies.user.userInfo.createTime))
        let now = Date()
        let accountAgeInDays = Calendar.autoupdatingCurrent.numberOfDays(between: accountCreationDate, and: now)
        return accountAgeBracket(for: accountAgeInDays)
    }
}

private extension UpsellTelemetryReporter {
    enum EventName: String {
        case upsellButtonTapped = "upsell_button_tapped"
        case upgradeAttempt = "upgrade_attempt"
        case upgradeSuccess = "upgrade_success"
    }

    struct Dimensions {
        let planBeforeUpgrade: String
        let daysSinceAccountCreation: String
        let upsellModalVersion: String
        var selectedPlan: String?

        var asDictionary: [String: String] {
            [
                "plan_before_upgrade": planBeforeUpgrade,
                "days_since_account_creation": daysSinceAccountCreation,
                "upsell_modal_version": upsellModalVersion,
                "selected_plan": selectedPlan
            ].compactMapValues { $0 }
        }
    }

    var measurementGroup: String {
        "mail.any.upsell"
    }

    var upsellModalVersion: String {
        "A.1"
    }

    func accountAgeBracket(for accountAgeInDays: Int) -> String {
        let validBrackets: [ClosedRange<Int>] = [
            1...3,
            4...10,
            11...30,
            31...60
        ]

        if accountAgeInDays == 0 {
            return "0"
        } else if let matchingBracket = validBrackets.first(where: { $0.contains(accountAgeInDays) }) {
            return "\(matchingBracket.lowerBound)-\(matchingBracket.upperBound)"
        } else if let maximumUpperBound = validBrackets.map(\.upperBound).max(), accountAgeInDays > maximumUpperBound {
            return ">\(maximumUpperBound)"
        } else {
            return "n/a"
        }
    }
}

private extension Calendar {
    func numberOfDays(between startDate: Date, and endDate: Date) -> Int {
        let fromDate = startOfDay(for: startDate)
        let toDate = startOfDay(for: endDate)
        let numberOfDays = dateComponents([.day], from: fromDate, to: toDate)
        return numberOfDays.day ?? 0
    }
}