//
//  ApexSyncBrandView.swift
//  Apex
//
//  Branded sync shell — logo gradient peak mark, glow ring, step timeline.
//

import SwiftUI

// MARK: - Background

struct ApexSyncBackground: View {
    var body: some View {
        ZStack {
            ApexBrandColors.backgroundGradient

            ApexBrandColors.heroGlow

            RadialGradient(
                colors: [ApexBrandColors.purple.opacity(0.16), .clear],
                center: UnitPoint(x: 0.88, y: 0.78),
                startRadius: 12,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Peak mark

struct ApexPeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.06))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.94))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.94))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.94))
        path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.94))
        path.closeSubpath()
        return path
    }
}

struct ApexSyncHero: View {
    let progress: Double
    let isAnimating: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(ApexBrandColors.blue.opacity(0.15), lineWidth: 2)
                .frame(width: 132, height: 132)

            Circle()
                .trim(from: 0, to: max(0.04, progress))
                .stroke(
                    ApexBrandColors.logoGradient,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 132, height: 132)
                .animation(.easeInOut(duration: 0.45), value: progress)

            if isAnimating {
                Circle()
                    .stroke(ApexBrandColors.purple.opacity(pulse ? 0.05 : 0.22), lineWidth: 1)
                    .frame(width: pulse ? 156 : 142, height: pulse ? 156 : 142)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
            }

            ApexPeakShape()
                .fill(ApexBrandColors.logoGradient)
                .frame(width: 52, height: 52)
                .shadow(color: ApexBrandColors.purple.opacity(0.5), radius: 18, y: 6)
        }
        .onAppear { pulse = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Step row

struct ApexSyncStepRow: View {
    let step: SyncStep
    let state: SyncStepState
    let detail: String
    let fraction: Double
    var compact: Bool = false

    private var barGradient: LinearGradient { ApexBrandColors.logoGradient }

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 12 : 14) {
            stepIndicator

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.title)
                        .font(compact ? .subheadline : .body)
                        .fontWeight(state == .active ? .semibold : .regular)
                        .foregroundStyle(titleColor)

                    Spacer(minLength: 8)

                    if state == .active {
                        if fraction > 0 {
                            Text("\(Int((fraction * 100).rounded()))%")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ApexBrandColors.blue)
                                .monospacedDigit()
                        }
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                        }
                    }
                }

                if state == .active, fraction > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(ApexBrandColors.blue.opacity(0.12))
                            Capsule()
                                .fill(barGradient)
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(.vertical, compact ? 4 : 6)
        .opacity(state == .pending ? 0.55 : 1)
    }

    @ViewBuilder
    private var stepIndicator: some View {
        switch state {
        case .pending:
            Image(systemName: step.systemImage)
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(width: 28, height: 28)
        case .active:
            ZStack {
                Circle()
                    .fill(ApexBrandColors.blue.opacity(0.15))
                Image(systemName: step.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ApexBrandColors.blue)
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
            .frame(width: 28, height: 28)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(ApexBrandColors.purple)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)
        }
    }

    private var titleColor: Color {
        switch state {
        case .pending: .secondary
        case .active, .completed: .primary
        }
    }
}

#if os(tvOS)

struct ApexSyncHeroTV: View {
    let progress: Double
    let isAnimating: Bool

    var body: some View {
        ApexSyncHero(progress: progress, isAnimating: isAnimating)
            .scaleEffect(1.35)
    }
}

#endif
