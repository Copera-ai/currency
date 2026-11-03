import Charts
import CurrencyKit
import SwiftUI

/// 7-day trend line for a pair row, colored by direction. Loads lazily.
struct Sparkline: View {
    let pair: CurrencyPair
    var range: HistoryRange = .week

    @Environment(AppModel.self) private var model

    var body: some View {
        let history = model.history.history(pair, range)
        ZStack {
            if let history, history.points.count > 1 {
                SparklineChart(history: history)
                    .transition(.opacity)
            } else if case .failed = model.history.phase(pair, range) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 1.5)
            } else {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 6)
                    .opacity(0.6)
            }
        }
        .animation(.easeOut(duration: 0.25), value: history?.points.count)
        .accessibilityHidden(true)
        // Re-runs each time the popover opens (CurrencyKit memoizes recent series).
        .task(id: model.isPopoverShown) {
            guard model.isPopoverShown else { return }
            await model.history.load(pair, range)
        }
    }
}

private struct SparklineChart: View {
    let history: PairHistory

    var body: some View {
        let color = Trend(change: history.change).color
        let low = history.low ?? 0
        let high = history.high ?? 1
        let pad = max((high - low) * 0.1, abs(high) * 0.0005)
        Chart(history.points) { point in
            AreaMark(
                x: .value("Date", point.date),
                yStart: .value("Base", low - pad),
                yEnd: .value("Rate", point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))

            LineMark(x: .value("Date", point.date), y: .value("Rate", point.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartPlotStyle { $0.clipped() }
    }
}

// MARK: - Detail

/// Expanded row: interactive chart with range picker, hover readout, low/high and actions.
struct PairDetailView: View {
    let tracked: TrackedPair

    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var range: HistoryRange?
    @State private var hovered: HistoryPoint?

    private var pair: CurrencyPair { tracked.pair }
    private var currentRange: HistoryRange { range ?? store.defaultRange(for: pair) }

    var body: some View {
        let history = model.history.history(pair, currentRange)
        VStack(alignment: .leading, spacing: 10) {
            Picker("Range", selection: Binding(get: { currentRange }, set: { newRange in
                withMotion(reduceMotion) { range = newRange }
            })) {
                ForEach(store.availableRanges(for: pair)) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            readout(history)
            chart(history)
                .frame(height: 128)
            stats(history)
            actions
        }
        .padding(.top, 2)
        .task(id: currentRange) {
            hovered = nil
            await model.history.load(pair, currentRange)
        }
    }

    // MARK: Readout

    private func readout(_ history: PairHistory?) -> some View {
        let value = hovered?.value ?? store.quote(for: pair)?.price
        let change = rangeChange(history)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(store.formatter.string(from: value))
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text(pair.quote)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let hovered {
                Text(hovered.date, format: dateFormat)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let change {
                HStack(spacing: 4) {
                    ChangePill(change: change, formatter: store.formatter)
                    Text(currentRange.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private func rangeChange(_ history: PairHistory?) -> Double? {
        guard let first = history?.points.first?.value, first != 0,
              let last = store.quote(for: pair)?.price ?? history?.points.last?.value else { return history?.change }
        return (last - first) / first
    }

    private var dateFormat: Date.FormatStyle {
        currentRange == .day
            ? .dateTime.weekday(.abbreviated).hour().minute()
            : .dateTime.month(.abbreviated).day().year()
    }

    // MARK: Chart

    @ViewBuilder
    private func chart(_ history: PairHistory?) -> some View {
        if let history, history.points.count > 1 {
            DetailChart(history: history, hovered: $hovered, formatter: store.formatter)
                .opacity(model.history.phase(pair, currentRange) == .loading ? 0.5 : 1)
        } else if case .failed(let message) = model.history.phase(pair, currentRange) {
            VStack(spacing: 6) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await model.history.load(pair, currentRange) }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ChartPlaceholder()
        }
    }

    // MARK: Stats & actions

    private func stats(_ history: PairHistory?) -> some View {
        HStack(spacing: 0) {
            stat("Low", history?.low)
            stat("High", history?.high)
            stat("24h", store.quote(for: pair)?.change24h, isPercent: true)
        }
        .padding(.vertical, 8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func stat(_ title: String, _ value: Double?, isPercent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(isPercent ? store.formatter.percent(value) : store.formatter.string(from: value))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(isPercent ? Trend(change: value).color : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button {
                model.useInConverter(pair)
            } label: {
                Label("Convert", systemImage: "arrow.left.arrow.right")
            }
            Button {
                model.copyRate(of: pair)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(store.quote(for: pair) == nil)
            Spacer()
            Button {
                store.toggleFavorite(tracked.id)
            } label: {
                Image(systemName: tracked.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(tracked.isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.primary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(tracked.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(tracked.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            Button {
                store.toggleShowInMenuBar(tracked.id)
            } label: {
                Image(systemName: tracked.showInMenuBar ? "menubar.rectangle" : "menubar.dock.rectangle")
                    .foregroundStyle(tracked.showInMenuBar ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .help(tracked.showInMenuBar ? "Hide from Menu Bar" : "Show in Menu Bar")
            .accessibilityLabel(tracked.showInMenuBar ? "Hide from Menu Bar" : "Show in Menu Bar")
        }
        .buttonStyle(.glass)
        .tint(nil)
        .controlSize(.small)
        .font(.system(size: 11, weight: .medium))
    }
}

/// The interactive chart: area + line, hover or drag to scrub.
private struct DetailChart: View {
    let history: PairHistory
    @Binding var hovered: HistoryPoint?
    let formatter: RateFormatter

    var body: some View {
        let color = Trend(change: history.change).color
        let low = history.low ?? 0
        let high = history.high ?? 1
        let pad = max((high - low) * 0.12, abs(high) * 0.0005)
        Chart {
            ForEach(history.points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", low - pad),
                    yEnd: .value("Rate", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))

                LineMark(x: .value("Date", point.date), y: .value("Rate", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let hovered {
                RuleMark(x: .value("Date", hovered.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Date", hovered.date), y: .value("Rate", hovered.value))
                    .symbolSize(60)
                    .foregroundStyle(color)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: history.range == .day ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                    .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatter.string(from: number)).font(.system(size: 9).monospacedDigit())
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hovered = nearest(to: location, proxy: proxy, geometry: geometry)
                        case .ended: hovered = nil
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { hovered = nearest(to: $0.location, proxy: proxy, geometry: geometry) }
                        .onEnded { _ in hovered = nil })
            }
        }
        .accessibilityLabel("Price chart")
        .accessibilityValue(accessibilitySummary)
    }

    private func nearest(to location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> HistoryPoint? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let x = location.x - geometry[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return history.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private var accessibilitySummary: String {
        "Low \(formatter.string(from: history.low)), high \(formatter.string(from: history.high)), change \(formatter.percent(history.change))"
    }
}

/// Soft placeholder while a chart loads.
private struct ChartPlaceholder: View {
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.fill.quaternary)
            .overlay {
                ProgressView()
                    .controlSize(.small)
                    .opacity(0.6)
            }
            .opacity(phase ? 0.6 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever()) { phase = true }
            }
            .accessibilityLabel("Loading chart")
    }
}
