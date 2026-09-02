//
//  AlmanacLocationSheet.swift
//  Triangulum
//

import SwiftUI
import MapKit

/// Location picker for the Almanac: Current Location, one search field with
/// `AppleSearchCompleter` suggestions, and the last selected fixed place.
/// Selecting a suggestion resolves it through `AlmanacLocationResolving`
/// (the view-model-owned resolver contract) before handing the resolved
/// location back. No favourites manager — the sheet stays a single picker.
struct AlmanacLocationSheet: View {
    let currentLocation: AlmanacLocation?
    let locationManager: LocationManager?
    @ObservedObject var completer: AppleSearchCompleter
    let resolver: any AlmanacLocationResolving
    let onSelectLocation: (AlmanacLocation) -> Void
    let onUseCurrentLocation: () -> Void

    @State private var searchText = ""
    @State private var isResolving = false
    @State private var resolutionErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private static let lookupFailedText = "Couldn't find that place — try another name."
    private static let timeZoneUnavailableText = "Couldn't determine that place's time zone — choose another."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CelSpace.lg) {
                currentLocationSection
                selectedPlaceSection
                searchSection
            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CelSpace.md)
        }
        .onAppear {
            // Fresh query each presentation; the completer object itself is
            // owned by the Almanac screen across presentations.
            searchText = ""
            resolutionErrorMessage = nil
            completer.queryFragment = ""
        }
        .onChange(of: searchText) { _, text in
            completer.queryFragment = text
            resolutionErrorMessage = nil
        }
        .overlay {
            if isResolving {
                ProgressView()
                    .tint(Color.celCyan)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.celSurfaceTop)
                    )
            }
        }
    }

    // MARK: - Current Location

    private var currentLocationSection: some View {
        VStack(alignment: .leading, spacing: CelSpace.xs) {
            Text("LOCATION MODE").celEyebrow(size: 10)

            Button {
                onUseCurrentLocation()
                if let locationManager, locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestLocationPermission()
                }
                dismiss()
            } label: {
                rowLabel(
                    icon: "location.fill",
                    tint: .celCyan,
                    title: "Current Location",
                    detail: currentLocationDetail,
                    isSelected: currentLocation?.mode == .current
                )
            }

            if let locationManager,
               locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                Button {
                    locationManager.openAppSettings()
                } label: {
                    HStack {
                        Text("Open Settings")
                            .font(.celLabel)
                            .foregroundStyle(Color.celCyan)
                        Spacer()
                    }
                    .padding(.leading, 34)
                }
            }
        }
    }

    private var currentLocationDetail: String {
        guard let locationManager else { return "Sun and tide times for your current position." }
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Location access is off — open Settings to allow it."
        case .notDetermined:
            return "Allow location access to follow your position."
        default:
            break
        }
        if currentLocation?.mode == .current, let currentLocation {
            return "Following \(currentLocation.displayName)."
        }
        return "Sun and tide times for your current position."
    }

    // MARK: - Last selected place

    @ViewBuilder
    private var selectedPlaceSection: some View {
        if let place = currentLocation, place.mode == .selected {
            VStack(alignment: .leading, spacing: CelSpace.xs) {
                Text("LAST SELECTED PLACE").celEyebrow(size: 10)
                Button {
                    dismiss()
                } label: {
                    rowLabel(
                        icon: "mappin.and.ellipse",
                        tint: .celGold,
                        title: AlmanacText.placeLine(place),
                        detail: "Fixed destination — the date strip stays in its time zone.",
                        isSelected: true
                    )
                }
            }
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: CelSpace.xs) {
            Text("SEARCH FOR A PLACE").celEyebrow(size: 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.celTextDim)
                TextField("City, region, or point of interest", text: $searchText)
                    .font(.celBody(14))
                    .foregroundStyle(Color.celText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.celTextFaint)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.celStroke.opacity(0.5), lineWidth: 0.5)
                    )
            )

            if let resolutionErrorMessage {
                CelInlineMessage(text: resolutionErrorMessage, color: .celRed)
            }

            if searchText.isEmpty {
                Text("Selecting a suggestion pins the Almanac to that destination and resets the date strip to its local today.")
                    .font(.celLabel)
                    .foregroundStyle(Color.celTextFaint)
                    .fixedSize(horizontal: false, vertical: true)
            } else if completer.results.isEmpty {
                Text("No suggestions yet — keep typing or check the name.")
                    .font(.celLabel)
                    .foregroundStyle(Color.celTextFaint)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(completer.results, id: \.self) { completion in
                        Button {
                            select(completion)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .font(.celBody(14, weight: .medium))
                                        .foregroundStyle(Color.celText)
                                        .multilineTextAlignment(.leading)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(Color.celTextFaint)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .disabled(isResolving)
                    }
                }
            }
        }
    }

    private func rowLabel(icon: String, tint: Color, title: String, detail: String, isSelected: Bool) -> some View {
        HStack(spacing: CelSpace.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.celBody(15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.celText : Color.celTextDim)
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.celTextFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.celCyan)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Resolution

    private func select(_ completion: MKLocalSearchCompletion) {
        guard !isResolving else { return }
        isResolving = true
        Task {
            do {
                let location = try await resolver.resolveSearchCompletion(completion)
                onSelectLocation(location)
                dismiss()
            } catch AlmanacLocationError.lookupFailed {
                resolutionErrorMessage = Self.lookupFailedText
            } catch AlmanacLocationError.timeZoneUnavailable {
                resolutionErrorMessage = Self.timeZoneUnavailableText
            } catch {
                resolutionErrorMessage = Self.lookupFailedText
            }
            isResolving = false
        }
    }
}
