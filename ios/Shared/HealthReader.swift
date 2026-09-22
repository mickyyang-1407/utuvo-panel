// HealthReader.swift — reads today's activity from HealthKit. Compiled into BOTH the app
// target and the PanelWidget extension (the extension now has the HealthKit entitlement,
// and queries on HKHealthStore are legal inside a widget timeline provider). Logic stays
// in Shared/Logic.swift so Check can exercise the pure pieces without HealthKit at all.

import HealthKit

enum HealthReader {
    /// Every quantity + activity summary the panel renders. Single source of truth — the
    /// app's `requestHealth()` and the widget's `build()` both read this.
    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.appleStandTime),
        HKObjectType.activitySummaryType(),
    ]

    /// Today's activity, read fresh. Returns `nil` when HealthKit is unavailable OR any
    /// query fails for any reason other than "no samples yet today" — callers keep what
    /// they had. Step / distance / ring values default to 0 on `noData`, so an empty day
    /// shows 0s rather than being dropped.
    static func today(store: HKHealthStore = HKHealthStore(), now: Date = Date()) async -> ActivitySnapshot? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)

        // Steps: cumulative sum for today. noData → 0; any other error → bail.
        switch await sum(of: .stepCount, unit: .count(), start: start, end: now, store: store) {
        case .error: return nil
        case .value(let steps), .empty(let steps):
            // Distance walked/run today.
            switch await sum(of: .distanceWalkingRunning, unit: .meter(), start: start, end: now, store: store) {
            case .error: return nil
            case .value(let distance), .empty(let distance):
                // Rings: today's activity summary. empty / noData → keep default goals.
                switch await summary(for: now, calendar: cal, store: store) {
                case .error: return nil
                case .value(let s):
                    return assemble(steps: Int(steps), distance: distance, summary: s, now: now)
                case .empty:
                    return assemble(steps: Int(steps), distance: distance, summary: nil, now: now)
                }
            }
        }
    }

    private static func assemble(steps: Int, distance: Double, summary: HKActivitySummary?, now: Date) -> ActivitySnapshot {
        var snap = ActivitySnapshot()
        snap.day = now
        snap.steps = steps
        snap.distanceMeters = distance
        if let s = summary {
            snap.moveKcal = s.activeEnergyBurned.doubleValue(for: .kilocalorie())
            snap.moveGoal = max(s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()), 1)
            snap.exerciseMinutes = Int(s.appleExerciseTime.doubleValue(for: .minute()))
            snap.exerciseGoal = max(s.appleExerciseTimeGoal.doubleValue(for: .minute()), 1)
            snap.standHours = Int(s.appleStandHours.doubleValue(for: .count()))
            snap.standGoal = max(s.appleStandHoursGoal.doubleValue(for: .count()), 1)
        }
        return snap
    }

    /// Cumulative sum for one quantity. `.empty` = noData → caller treats as 0.
    private static func sum(of id: HKQuantityTypeIdentifier, unit: HKUnit,
                            start: Date, end: Date, store: HKHealthStore) async -> SumResult {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end)
            let q = HKStatisticsQuery(
                quantityType: HKQuantityType(id),
                quantitySamplePredicate: pred,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    cont.resume(returning: .empty(0))
                    return
                }
                if error != nil {
                    cont.resume(returning: .error)
                    return
                }
                cont.resume(returning: .value(stats?.sumQuantity()?.doubleValue(for: unit) ?? 0))
            }
            store.execute(q)
        }
    }

    /// Today's activity summary. `.empty` = no rings yet (defaults stay); `.error` = abort.
    private static func summary(for now: Date, calendar: Calendar, store: HKHealthStore) async -> SummaryResult {
        await withCheckedContinuation { cont in
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.calendar = calendar
            let pred = HKQuery.predicateForActivitySummary(with: comps)
            let q = HKActivitySummaryQuery(predicate: pred) { _, summaries, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    cont.resume(returning: .empty)
                    return
                }
                if error != nil {
                    cont.resume(returning: .error)
                    return
                }
                cont.resume(returning: .value(summaries?.first))
            }
            store.execute(q)
        }
    }

    private enum SumResult {
        case empty(Double)
        case value(Double)
        case error
    }

    private enum SummaryResult {
        case empty
        case value(HKActivitySummary?)
        case error
    }
}