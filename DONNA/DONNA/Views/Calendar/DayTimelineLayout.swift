import Foundation

/// Pure column layout for the day timeline: items whose time ranges overlap are placed
/// side by side instead of on top of each other (the classic calendar "lanes" layout).
///
/// Algorithm: walk the items by start time, grouping transitively-overlapping items into
/// clusters. Inside a cluster each item takes the first column whose last item has already
/// ended; every item in the cluster then shares the cluster's column count, so widths line
/// up within one block of overlaps but non-overlapping parts of the day stay full width.
enum DayTimelineLayout {

    struct Input<ID: Hashable> {
        let id: ID
        let start: Date
        let end: Date
    }

    struct Slot: Equatable {
        /// Zero-based column the item is drawn in.
        let column: Int
        /// Number of columns in the item's overlap cluster (≥ 1).
        let columnCount: Int
    }

    /// `minimumDuration` mirrors the minimum drawn height, so two items that *look*
    /// overlapping on screen (e.g. a 5-minute item rendered 15 minutes tall) get lanes too.
    static func slots<ID: Hashable>(
        for items: [Input<ID>],
        minimumDuration: TimeInterval = 15 * 60
    ) -> [ID: Slot] {
        let sorted = items.sorted {
            $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end
        }

        var result: [ID: Slot] = [:]
        var cluster: [(id: ID, column: Int)] = []
        var columnEnds: [Date] = []   // effective end of the last item per column
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(1, columnEnds.count)
            for entry in cluster {
                result[entry.id] = Slot(column: entry.column, columnCount: count)
            }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for item in sorted {
            let end = max(item.end, item.start.addingTimeInterval(minimumDuration))

            if !cluster.isEmpty && item.start >= clusterEnd {
                flush()
                clusterEnd = .distantPast
            }

            if let free = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[free] = end
                cluster.append((item.id, free))
            } else {
                columnEnds.append(end)
                cluster.append((item.id, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, end)
        }
        flush()
        return result
    }
}
