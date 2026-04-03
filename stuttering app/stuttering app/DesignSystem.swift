//
//  DesignSystem.swift
//  stuttering app
//
//  Created by Codex on 4/2/26.
//

import SwiftUI

enum EasePalette {
    static let background = Color(red: 247 / 255, green: 243 / 255, blue: 238 / 255)
    static let surface = Color(red: 253 / 255, green: 250 / 255, blue: 245 / 255)
    static let primaryText = Color(red: 54 / 255, green: 47 / 255, blue: 42 / 255)
    static let secondaryText = Color(red: 146 / 255, green: 140 / 255, blue: 133 / 255)
    static let outline = Color(red: 233 / 255, green: 228 / 255, blue: 221 / 255)
    static let sage = Color(red: 122 / 255, green: 158 / 255, blue: 126 / 255)
    static let sageSoft = Color(red: 201 / 255, green: 220 / 255, blue: 202 / 255)
    static let mistBlue = Color(red: 227 / 255, green: 235 / 255, blue: 242 / 255)
    static let warmSand = Color(red: 247 / 255, green: 239 / 255, blue: 226 / 255)
}

struct EaseCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EasePalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(EasePalette.outline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct EasePrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(EasePalette.sage)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
