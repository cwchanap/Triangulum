//
//  SnapshotCreationView.swift
//  Triangulum
//
//  Extracted from ContentView.swift
//

import SwiftUI
import PhotosUI
import UIKit
import os

/// Pairs a PhotosPickerItem with its loaded preview image for identity-based removal
private struct PairedPreviewItem: Identifiable {
    let id: UUID = UUID()
    let pickerItem: PhotosPickerItem
    let image: UIImage
}

/// Wraps a captured camera image with a stable identity for SwiftUI ForEach
private struct CapturedImageItem: Identifiable {
    let id: UUID = UUID()
    let image: UIImage
}

struct SnapshotCreationView: View {
    @Binding var snapshot: SensorSnapshot?
    let snapshotManager: SnapshotManager
    @Binding var isPresented: Bool

    @State private var tempSelectedPhotos: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var showingCamera = false
    @State private var capturedImages: [CapturedImageItem] = []
    @State private var pairedPreviewItems: [PairedPreviewItem] = []
    /// Tracks the in-flight Task that loads photo previews so it can be cancelled
    /// when the selection changes or the view is dismissed.
    @State private var previewLoadingTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Success Icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.prussianSuccess)
                    .padding(.top, 20)

                // Title and Message
                headerSection

                // Enhanced Photo Section
                photoSection

                Spacer()

                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: saveSnapshot) {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Save Snapshot")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.prussianBlue)
                        .cornerRadius(12)
                    }
                    .disabled(isProcessingPhotos)

                    Button("Skip Photos", action: saveSnapshotWithoutPhotos)
                        .font(.callout)
                        .foregroundColor(.prussianBlueLight)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("New Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        // Cancel any in-flight preview loading, reset state, and dismiss.
                        previewLoadingTask?.cancel()
                        previewLoadingTask = nil
                        isProcessingPhotos = false
                        tempSelectedPhotos.removeAll()
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onChange(of: tempSelectedPhotos) { oldPhotos, newPhotos in
            // Diff to handle additions vs removals incrementally
            let addedPhotos = newPhotos.filter { !oldPhotos.contains($0) }
            let removedPhotos = oldPhotos.filter { !newPhotos.contains($0) }
            
            // Remove corresponding entries for deselected photos (no async needed)
            if !removedPhotos.isEmpty {
                pairedPreviewItems.removeAll { pair in
                    removedPhotos.contains(pair.pickerItem)
                }
                // Cancel any in-flight decode that may still append previews for
                // the removed photos, which would re-introduce stale thumbnails.
                previewLoadingTask?.cancel()
                previewLoadingTask = nil
            }
            
            // Load previews only for newly added photos
            if !addedPhotos.isEmpty {
                isProcessingPhotos = true
                previewLoadingTask?.cancel()
                previewLoadingTask = Task {
                    await loadPhotoPreviewImagesForNewItems(addedPhotos)
                    await MainActor.run {
                        isProcessingPhotos = false
                    }
                }
            }
        }
    }

    // MARK: - Extracted Subviews

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Snapshot Captured!")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.prussianBlueDark)

            Text(
                "Sensor data has been recorded at " +
                "\(snapshot?.timestamp.formatted(date: .omitted, time: .shortened) ?? "now")"
            )
                .font(.body)
                .foregroundColor(.prussianBlueLight)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var photoSection: some View {
        VStack(spacing: 16) {
            // Header with photo count
            HStack {
                Text("\u{1F4F7} Add Photos (Optional)")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)

                Spacer()

                if !capturedImages.isEmpty || !pairedPreviewItems.isEmpty {
                    let totalPhotos = capturedImages.count + pairedPreviewItems.count
                    Text("\(totalPhotos)/5")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.prussianBlueLight.opacity(0.1))
                        .cornerRadius(6)
                }
            }

            // Photo Action Buttons
            HStack(spacing: 12) {
                Button {
                    showingCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera")
                        Text("Camera")
                    }
                    .font(.callout)
                    .foregroundColor(.prussianBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.prussianBlueLight.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(capturedImages.count + tempSelectedPhotos.count >= 5)

                PhotosPicker(
                    selection: $tempSelectedPhotos,
                    maxSelectionCount: max(0, 5 - capturedImages.count),
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Library")
                    }
                    .font(.callout)
                    .foregroundColor(.prussianBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.prussianBlueLight.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(capturedImages.count + tempSelectedPhotos.count >= 5)

                Spacer()
            }

            // Photo Preview Grid
            photoPreviewGrid

            if isProcessingPhotos {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing photos...")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
        .padding(.horizontal)
        .sheet(isPresented: $showingCamera) {
            ImagePicker(sourceType: .camera) { image in
                if capturedImages.count + tempSelectedPhotos.count < 5 {
                    capturedImages.append(CapturedImageItem(image: image))
                }
            }
        }
    }

    @ViewBuilder
    private var photoPreviewGrid: some View {
        if !capturedImages.isEmpty || !pairedPreviewItems.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(capturedImages) { item in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: item.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(8)

                        Button {
                            capturedImages.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .font(.caption)
                        }
                        .offset(x: 5, y: -5)
                    }
                }

                ForEach(pairedPreviewItems) { pair in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: pair.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(8)

                        Button {
                            let pickerItem = pair.pickerItem
                            pairedPreviewItems.removeAll { $0.id == pair.id }
                            tempSelectedPhotos.removeAll { $0 == pickerItem }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .font(.caption)
                        }
                        .offset(x: 5, y: -5)
                    }
                }
            }
            .padding(.top, 8)
        } else {
            Text("Take photos with camera or select from your photo library")
                .font(.caption)
                .foregroundColor(.prussianBlueLight)
                .italic()
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func saveSnapshot() {
        guard let snapshot = snapshot else { return }
        // Prevent re-entry on rapid taps; isProcessingPhotos is also reflected in
        // the button's .disabled modifier but we guard here for safety.
        guard !isProcessingPhotos else { return }
        isProcessingPhotos = true

        // Add the snapshot first
        snapshotManager.addSnapshot(snapshot)

        // Process captured images directly
        for item in capturedImages {
            snapshotManager.addPhoto(to: snapshot.id, image: item.image)
        }

        // Then process photos from library if any
        if !tempSelectedPhotos.isEmpty {
            Task {
                await processSelectedPhotos(for: snapshot.id)
                await MainActor.run {
                    finishSaving()
                }
            }
        } else {
            finishSaving()
        }
    }

    private func saveSnapshotWithoutPhotos() {
        guard let snapshot = snapshot else { return }
        snapshotManager.addSnapshot(snapshot)
        finishSaving()
    }

    private func finishSaving() {
        isPresented = false
        tempSelectedPhotos.removeAll()
        isProcessingPhotos = false
    }

    private func processSelectedPhotos(for snapshotID: UUID) async {
        // Build an identity map from PhotosPickerItem to its already-decoded preview image
        // so we don't re-decode images that were loaded during the preview pass.
        var previewMap: [PhotosPickerItem: UIImage] = [:]
        for pair in pairedPreviewItems {
            previewMap[pair.pickerItem] = pair.image
        }

        for photoItem in tempSelectedPhotos {
            if let image = previewMap[photoItem] {
                // Reuse the preview-pass decode
                await MainActor.run {
                    _ = snapshotManager.addPhoto(to: snapshotID, image: image)
                }
            } else {
                // Fallback: decode from the picker item (failed preview or new item)
                do {
                    if let data = try await photoItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            _ = snapshotManager.addPhoto(to: snapshotID, image: image)
                        }
                    }
                } catch {
                    Logger.snapshot.error("Failed to process photo: \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadPhotoPreviewImages(from photoItems: [PhotosPickerItem]) async {
        var newPairs: [PairedPreviewItem] = []

        for photoItem in photoItems {
            do {
                if let data = try await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    newPairs.append(PairedPreviewItem(pickerItem: photoItem, image: image))
                }
            } catch {
                Logger.snapshot.error("Failed to load preview image: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            pairedPreviewItems = newPairs
        }
    }

    /// Loads preview images only for newly added photos and appends them to pairedPreviewItems.
    /// Used by onChange to incrementally update without reloading existing items.
    private func loadPhotoPreviewImagesForNewItems(_ newPhotoItems: [PhotosPickerItem]) async {
        var newPairs: [PairedPreviewItem] = []

        for photoItem in newPhotoItems {
            do {
                if let data = try await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    newPairs.append(PairedPreviewItem(pickerItem: photoItem, image: image))
                }
            } catch {
                Logger.snapshot.error("Failed to load preview image: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            pairedPreviewItems.append(contentsOf: newPairs)
        }
    }
}
