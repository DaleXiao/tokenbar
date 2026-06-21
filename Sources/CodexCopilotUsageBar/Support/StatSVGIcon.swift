import AppKit
import SwiftUI

enum StatSVGIcon {
  case today
  case allTime
  case input
  case cacheRead
  case output
  case aiu

  var image: NSImage {
    let image = NSImage(data: Data(svg.utf8)) ?? NSImage(size: NSSize(width: 24, height: 24))
    image.isTemplate = true
    return image
  }

  private var svg: String {
    switch self {
    case .today:
      return """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <rect x="3.5" y="4.5" width="17" height="16" rx="2.5"/>
        <path d="M8 3v4M16 3v4M3.5 9h17"/>
      </svg>
      """
    case .allTime:
      return """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M3 12a9 9 0 1 0 3-6.7"/>
        <path d="M3 5v5h5"/>
        <path d="M12 7v5l3 2"/>
      </svg>
      """
    case .input:
      return """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M12 3v12"/>
        <path d="m7 10 5 5 5-5"/>
        <path d="M4 20h16"/>
      </svg>
      """
    case .cacheRead:
      return """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <ellipse cx="12" cy="6" rx="7" ry="3"/>
        <path d="M5 6v8c0 1.7 3.1 3 7 3s7-1.3 7-3V6"/>
        <path d="M5 10c0 1.7 3.1 3 7 3s7-1.3 7-3"/>
        <path d="M10 20h4M12 17v3"/>
      </svg>
      """
    case .output:
      return """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M12 21V9"/>
        <path d="m7 14 5-5 5 5"/>
        <path d="M4 4h16"/>
      </svg>
      """
    case .aiu:
      return """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <rect x="6" y="6" width="12" height="12" rx="3"/>
        <path d="M9 3v3M12 3v3M15 3v3"/>
        <path d="M9 18v3M12 18v3M15 18v3"/>
        <path d="M3 9h3M3 12h3M3 15h3"/>
        <path d="M18 9h3M18 12h3M18 15h3"/>
        <path d="M9 14a3 3 0 0 1 6 0"/>
        <path d="M12 14l2-2"/>
      </svg>
      """
    }
  }
}

struct StatSVGIconView: View {
  let icon: StatSVGIcon

  var body: some View {
    Image(nsImage: icon.image)
      .resizable()
      .renderingMode(.template)
      .scaledToFit()
      .foregroundStyle(.secondary)
      .frame(width: 18, height: 18)
      .accessibilityHidden(true)
  }
}

enum ModelProviderSVGIcon {
  case openAI
  case claude
  case generic

  init(model: String) {
    let lowercased = model.lowercased()
    if lowercased.hasPrefix("gpt") || lowercased.hasPrefix("openai") {
      self = .openAI
    } else if lowercased.hasPrefix("claude") || lowercased.contains("anthropic") {
      self = .claude
    } else {
      self = .generic
    }
  }

  var image: NSImage {
    switch self {
    case .openAI:
      if let image = bundledImage(named: "openai") {
        return image
      }
    case .claude:
      if let image = bundledImage(named: "anthropic") {
        return image
      }
    case .generic:
      break
    }

    let image = NSImage(data: Data(svg.utf8)) ?? NSImage(size: NSSize(width: 24, height: 24))
    image.isTemplate = true
    return image
  }

  private func bundledImage(named name: String) -> NSImage? {
    guard let url = Bundle.main.resourceURL?
      .appendingPathComponent("ModelIcons")
      .appendingPathComponent("\(name).png"),
      let image = NSImage(contentsOf: url)
    else {
      return nil
    }
    image.isTemplate = true
    return image
  }

  private var svg: String {
    switch self {
    case .openAI:
      return """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
        <path d="M12 3.5c1.5-1 3.6-.4 4.4 1.2.4.8.4 1.7.1 2.5 1.8.1 3.2 1.6 3.2 3.4 0 1-.4 1.9-1.1 2.5.8 1.7.1 3.8-1.6 4.6-.8.4-1.8.5-2.6.2-.9 1.5-2.9 2.1-4.5 1.2-.8-.4-1.4-1.1-1.7-1.9-1.8-.1-3.2-1.6-3.2-3.4 0-1 .4-1.9 1.1-2.5-.8-1.7-.1-3.8 1.6-4.6.8-.4 1.8-.5 2.6-.2.4-1.2 1-2.2 1.7-3Z"/>
        <path d="M8.2 17.2v-6.4l5.5-3.2"/>
        <path d="m6.1 11.3 5.5 3.2 5.5-3.2"/>
        <path d="M10.3 6.5 15.8 9.7v6.4"/>
      </svg>
      """
    case .claude:
      return """
      <svg fill="black" role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
        <path d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"/>
      </svg>
      """
    case .generic:
      return """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <rect x="4" y="5" width="16" height="14" rx="3"/>
        <path d="M8 10h8M8 14h5"/>
      </svg>
      """
    }
  }
}

struct ModelProviderSVGIconView: View {
  let model: String
  let color: Color

  var body: some View {
    Image(nsImage: ModelProviderSVGIcon(model: model).image)
      .resizable()
      .renderingMode(.template)
      .scaledToFit()
      .foregroundStyle(color)
      .frame(width: 17, height: 17)
      .accessibilityHidden(true)
  }
}
