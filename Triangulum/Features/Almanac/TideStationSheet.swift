//
//  TideStationSheet.swift
//  Triangulum
//

import SwiftUI

/// Manual station override picker: the currently selected station, at most
/// the eight nearest eligible alternatives, and **Use Nearest Station** to
/// clear an override and fall back to the automatic nearest selection.
struct TideStationSheet: View {
    let selectedStation: TideStation
    let alternatives: [TideStation]
    let onSelect: (TideStation) -> Void
    let onUseNearestStation: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CelSpace.lg) {
                VStack(alignment: .leading, spacing: CelSpace.xs) {
                    Text("USING").celEyebrow(size: 10)
                    stationRow(selectedStation, isSelected: true)
                }

                VStack(alignment: .leading, spacing: CelSpace.xs) {
                    Text("NEARBY STATIONS").celEyebrow(size: 10)
                    if visibleAlternatives.isEmpty {
                        Text("No other eligible station is within 250 km.")
                            .font(.celLabel)
                            .foregroundStyle(Color.celTextFaint)
                    } else {
                        ForEach(visibleAlternatives) { station in
                            stationRow(station, isSelected: station.id == selectedStation.id)
                        }
                    }
                }

                Button {
                    onUseNearestStation()
                } label: {
                    HStack {
                        Image(systemName: "location.circle")
                            .font(.system(size: 15, weight: .medium))
                        Text("Use Nearest Station")
                            .font(.celLabel)
                        Spacer()
                    }
                    .foregroundStyle(Color.celCyan)
                    .padding(CelSpace.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.celCyan.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.celCyan.opacity(0.35), lineWidth: 0.5)
                            )
                    )
                }

                CelInlineMessage(text: AlmanacTidesView.planningOnlyWarningText,
                                 icon: "info.circle.fill", color: .celCyan)
            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CelSpace.md)
        }
    }

    /// Defensive cap: the resolver already limits alternatives, but the sheet
    /// itself never lists more than the selector's maximum either.
    private var visibleAlternatives: [TideStation] {
        Array(alternatives
            .filter { $0.id != selectedStation.id }
            .prefix(TideStationSelector.maximumAlternatives))
    }

    private func stationRow(_ station: TideStation, isSelected: Bool) -> some View {
        Button {
            onSelect(station)
        } label: {
            HStack(spacing: CelSpace.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.celBody(15, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.celText : Color.celTextDim)
                        .multilineTextAlignment(.leading)
                    Text(station.datumLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.celTextFaint)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.celCyan)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
    }
}
