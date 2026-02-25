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
    /// Tracks the in-flight Task that saves photos so it can be cancelled via Cancel.
    @State private var saveTask: Task<Void, Never>?

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
                        // Cancel any in-flight preview loading or photo saving, reset state, and dismiss.
                        previewLoadingTask?.cancel()
                        previewLoadingTask = nil
                        saveTask?.cancel()
                        saveTask = nil
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
                // Only clear the spinner when no save is in flight.
                // isProcessingPhotos also guards saveSnapshot() re-entry, so
                // resetting it while saveTask is running would re-enable the
                // Save button and allow a concurrent duplicate save.
                if saveTask == nil {
                    isProcessingPhotos = false
                }
            }
            
            // Load previews only for newly added photos
            if !addedPhotos.isEmpty {
                // Cancel any in-flight preview task before starting a new one.
                previewLoadingTask?.cancel()
                previewLoadingTask = nil
                // Only reset the spinner state when no save is in flight.
                // isProcessingPhotos also guards saveSnapshot() re-entry, so
                // briefly setting it false while saveTask is running would
                // enable the Save button for a frame and risk a concurrent save.
                if saveTask == nil {
                    isProcessingPhotos = false
                }
                isProcessingPhotos = true
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

        // Capture mutable state before entering the async context so that
        // a Cancel tap (which clears these arrays on the main actor) does
        // not race with the in-flight task.
        let cameraImages = capturedImages.map { $0.image }
        let selectedPhotosSnapshot = tempSelectedPhotos
        // Reuse already-decoded preview images to avoid a second decode pass.
        // Use uniquingKeysWith to safely handle any duplicate PhotosPickerItems
        // that a cancelled preview task may have appended before it was stopped.
        // Keeping the latest entry (second closure argument) is arbitrary but safe.
        let previewMap: [PhotosPickerItem: UIImage] = Dictionary(
            pairedPreviewItems.map { ($0.pickerItem, $0.image) },
            uniquingKeysWith: { _, latest in latest }
        )

        saveTask = Task {
            // Phase 1 — collect every library image before touching persistent storage.
            var libraryImages: [UIImage] = []
            for photoItem in selectedPhotosSnapshot {
                guard !Task.isCancelled else { return }
                if let image = previewMap[photoItem] {
                    // Reuse the preview-pass decode
                    libraryImages.append(image)
                } else {
                    // Fallback: decode from the picker item (failed preview or new item)
                    do {
                        if let data = try await photoItem.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            libraryImages.append(image)
                        }
                    } catch {
                        Logger.snapshot.error("Failed to process photo: \(error.localizedDescription)")
                    }
                }
            }

            // Phase 2 — only write to storage when the save was not cancelled.
            // We check Task.isCancelled before the MainActor hop, but we must
            // re-check immediately inside MainActor.run as well: cancellation
            // can be signalled while awaiting the hop itself, and the block
            // would otherwise still run on the main actor with stale "not
            // cancelled" state, persisting the snapshot against the user's intent.
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                snapshotManager.addSnapshot(snapshot)
                for image in cameraImages + libraryImages {
                    snapshotManager.addPhoto(to: snapshot.id, image: image)
                }
                saveTask = nil
                finishSaving()
            }
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

    /// Loads preview images only for newly added photos and appends them to pairedPreviewItems.
    /// Used by onChange to incrementally update without reloading existing items.
    private func loadPhotoPreviewImagesForNewItems(_ newPhotoItems: [PhotosPickerItem]) async {
        var newPairs: [PairedPreviewItem] = []

        for photoItem in newPhotoItems {
            // Check cancellation at each iteration boundary. Flush any pairs
            // already decoded in this task run so they are not lost — a follow-up
            // onChange only processes the diff (newly added items), so discarding
            // mid-task work would leave those photos permanently without previews.
            // IMPORTANT: filter against the current selection before flushing.
            // If cancellation was triggered by a photo deselection, newPairs may
            // contain items for the just-removed photos; appending them would
            // re-introduce stale thumbnails that the removal handler already cleared.
            if Task.isCancelled {
                await MainActor.run {
                    let current = tempSelectedPhotos
                    let validPairs = newPairs.filter { current.contains($0.pickerItem) }
                    pairedPreviewItems.append(contentsOf: validPairs)
                }
                return
            }
            do {
                if let data = try await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    newPairs.append(PairedPreviewItem(pickerItem: photoItem, image: image))
                }
            } catch is CancellationError {
                // Task was cancelled mid-transfer — flush only still-selected pairs.
                await MainActor.run {
                    let current = tempSelectedPhotos
                    let validPairs = newPairs.filter { current.contains($0.pickerItem) }
                    pairedPreviewItems.append(contentsOf: validPairs)
                }
                return
            } catch {
                Logger.snapshot.error("Failed to load preview image: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            pairedPreviewItems.append(contentsOf: newPairs)
        }
    }
}
