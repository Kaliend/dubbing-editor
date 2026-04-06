import SwiftUI

struct SpeakerColorsPanelView: View {
    @ObservedObject var model: EditorViewModel
    let showCloseButton: Bool
    let onClose: () -> Void

    private var speakers: [EditorViewModel.SpeakerStatistic] {
        model
            .speakerStatistics()
            .sorted { lhs, rhs in
                lhs.speaker.localizedCaseInsensitiveCompare(rhs.speaker) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if speakers.isEmpty {
                Text("V projektu zatim nejsou zadne postavy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(speakers, id: \.speaker) { stat in
                            speakerRow(for: stat)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Text("Kdyz neni nastavena vlastni barva, pouzije se stabilni vychozi barva odvozena z nazvu postavy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 760, minHeight: 430)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Barvy postav")
                .font(.title3.weight(.semibold))

            Spacer()

            Text("Celkem: \(speakers.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showCloseButton {
                Button("Zavrit") {
                    onClose()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func speakerRow(for stat: EditorViewModel.SpeakerStatistic) -> some View {
        let appearance = model.speakerAppearance(for: stat.speaker)
        let overridePaletteID = model.speakerColorOverridePaletteID(for: stat.speaker)
        let resolvedPaletteID = appearance?.paletteID

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                speakerPreviewChip(speaker: stat.speaker, appearance: appearance)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(overridePaletteID == nil ? "Auto" : "Vlastni")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Default") {
                    model.resetSpeakerColorOverride(for: stat.speaker)
                }
                .buttonStyle(.bordered)
                .disabled(overridePaletteID == nil)
            }

            HStack(spacing: 6) {
                ForEach(SpeakerAppearanceService.curatedPaletteIDs, id: \.self) { paletteID in
                    paletteButton(
                        paletteID: paletteID,
                        isSelected: resolvedPaletteID == paletteID,
                        isExplicitOverride: overridePaletteID == paletteID,
                        speaker: stat.speaker
                    )
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func speakerPreviewChip(
        speaker: String,
        appearance: SpeakerAppearance?
    ) -> some View {
        HStack(spacing: 8) {
            if let appearance {
                Circle()
                    .fill(appearance.swatchColor)
                    .frame(width: 10, height: 10)
            }

            Text(speaker)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(appearance?.fieldFillColor ?? Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(appearance?.fieldBorderColor ?? Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func paletteButton(
        paletteID: SpeakerColorPaletteID,
        isSelected: Bool,
        isExplicitOverride: Bool,
        speaker: String
    ) -> some View {
        Button {
            model.setSpeakerColorOverride(for: speaker, paletteID: paletteID.rawValue)
        } label: {
            Circle()
                .fill(SpeakerAppearanceService.swatchColor(for: paletteID))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.primary.opacity(0.85) : Color.clear, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .stroke(isExplicitOverride ? Color.white.opacity(0.8) : Color.clear, lineWidth: 1)
                        .padding(3)
                )
        }
        .buttonStyle(.plain)
        .help(isExplicitOverride ? "\(paletteID.displayName) (override)" : paletteID.displayName)
    }
}
