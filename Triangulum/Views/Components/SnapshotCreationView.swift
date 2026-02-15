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

struct SnapshotCreationView: View {
    @Binding var snapshot: SensorSnapshot?
    let snapshotManager: SnapshotManager
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var isPresented: Bool

    @State private var tempSelectedPhotos: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var capturedImages: [UIImage] = []
    @State private var photoPreviewImages: [UIImage] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Success Icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.prussianSuccess)
                    .padding(.top, 20)

                // Title and Message
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

                // Enhanced Photo Section
                VStack(spacing: 16) {
                    // Header with photo count
                    HStack {
                        Text("\u{1F4F7} Add Photos (Optional)")
                            .font(.headline)
                            .foregroundColor(.prussianBlueDark)

                        Spacer()

                        if !capturedImages.isEmpty || !photoPreviewImages.isEmpty {
                            let totalPhotos = capturedImages.count + photoPreviewImages.count
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
                        // Camera Button
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
                        .disabled(capturedImages.count + photoPreviewImages.count >= 5)

                        // Photo Library Button
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
                        .disabled(capturedImages.count + photoPreviewImages.count >= 5)

                        Spacer()
                    }

                    // Photo Preview Grid
                    if !capturedImages.isEmpty || !photoPreviewImages.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            // Show captured images first
                            ForEach(Array(capturedImages.enumerated()), id: \.offset) { index, image in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .cornerRadius(8)

                                    Button {
                                        capturedImages.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.black.opacity(0.6)))
                                            .font(.caption)
                                    }
                                    .offset(x: 5, y: -5)
                                }
                            }

                            // Show library photos
                            ForEach(Array(photoPreviewImages.enumerated()), id: \.offset) { index, image in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .cornerRadius(8)

                                    Button {
                                        photoPreviewImages.remove(at: index)
                                        if index < tempSelectedPhotos.count {
                                            tempSelectedPhotos.remove(at: index)
                                        }
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
                        if capturedImages.count < 5 {
                            capturedImages.append(image)
                        }
                    }
                }

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
                        isPresented = false
                        tempSelectedPhotos.removeAll()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onChange(of: tempSelectedPhotos) { _, newPhotos in
            if !newPhotos.isEmpty {
                isProcessingPhotos = true
                // Process selected photos and create preview images
                Task {
                    await loadPhotoPreviewImages(from: newPhotos)
                    await MainActor.run {
                        isProcessingPhotos = false
                    }
                }
            }
        }
    }

    private func saveSnapshot() {
        guard let snapshot = snapshot else { return }

        // Add the snapshot first
        snapshotManager.addSnapshot(snapshot)

        // Process captured images directly
        for image in capturedImages {
            snapshotManager.addPhoto(to: snapshot.id, image: image)
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
        for photoItem in tempSelectedPhotos {
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

    private func loadPhotoPreviewImages(from photoItems: [PhotosPickerItem]) async {
        var newPreviewImages: [UIImage] = []

        for photoItem in photoItems {
            do {
                if let data = try await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    newPreviewImages.append(image)
                }
            } catch {
                Logger.snapshot.error("Failed to load preview image: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            photoPreviewImages = newPreviewImages
        }
    }
}
