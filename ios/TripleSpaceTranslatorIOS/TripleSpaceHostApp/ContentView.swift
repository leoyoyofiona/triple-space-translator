import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("How to use") {
                    Text("1. Open iPhone Settings > General > Keyboard > Keyboards.")
                    Text("2. Add keyboard: Triple Space Translator.")
                    Text("3. Enter the keyboard and enable Allow Full Access.")
                    Text("4. In ChatGPT/Claude/Grok/Gemini/WeChat input box, switch to this keyboard.")
                    Text("5. Type Chinese text, then press Space 3 times within 0.5s to translate to English.")
                }

                Section("Notes") {
                    Text("This keyboard extension only works when this keyboard is active.")
                    Text("iOS may block third-party keyboards in secure fields.")
                    Text("The extension uses Apple's Translation framework.")
                }
            }
            .navigationTitle("Triple Space iOS")
        }
    }
}

#Preview {
    ContentView()
}
