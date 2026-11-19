"""Seeds five known UI bugs into a copy of the iOS app, for scoring the GUI testers (bugs.json says what each one is).

Usage: python3 seed.py <copy of iOS-App>
Never run it on the real app, and only once on a fresh copy:
cp -R iOS-App /tmp/seeded/iOS-App && python3 docs/ai-gui-testing/seeded/seed.py /tmp/seeded/iOS-App
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1]) / "BellAI"


def edit(path, old, new, after=None):
    file = root / path
    text = file.read_text()
    found = text.index(old, text.index(after) if after else 0)
    file.write_text(text[:found] + new + text[found + len(old):])


# S1: Typo in the Settings title.
edit("Views/SettingsView.swift", 'Text("Settings")\n                    .font(.largeTitle', 'Text("Setings")\n                    .font(.largeTitle')

# S2: The Reset button overlaps Save and test.
edit(
    "Views/SettingsView.swift",
    '                            .background(surface, in: RoundedRectangle(cornerRadius: 12))\n                    }\n                    .disabled(isTestingServer)\n                }\n                .buttonStyle(.plain)',
    '                            .background(surface, in: RoundedRectangle(cornerRadius: 12))\n                    }\n                    .offset(x: -64)\n                    .disabled(isTestingServer)\n                }\n                .buttonStyle(.plain)',
)

# S3: The helper text under Server options is nearly invisible.
edit("Views/SettingsView.swift", ".foregroundStyle(muted)", ".foregroundStyle(Color(white: 0.92))", after="Where BellAI finds your Mac")

# S4: The Nutrition card's meal button has the wrong label.
edit("Views/Components/PhotoPickerButton.swift", 'Text("Log meal").font(.subheadline.weight(.semibold))', 'Text("Log workout").font(.subheadline.weight(.semibold))')

# S5: The close button on the BellAI screen does nothing.
edit("Views/Components/Bell/BellHeaderView.swift", "Button(action: onClose) {", "Button(action: {}) {")
