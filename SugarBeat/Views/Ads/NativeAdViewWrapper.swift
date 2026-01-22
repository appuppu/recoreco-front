//
//  NativeAdViewWrapper.swift
//  SugarBeat
//

import SwiftUI
import GoogleMobileAds

struct NativeAdViewWrapper: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()

        // Create and configure the view hierarchy
        let containerStack = UIStackView()
        containerStack.axis = .vertical
        containerStack.spacing = 0
        containerStack.translatesAutoresizingMaskIntoConstraints = false

        // Header stack
        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.spacing = 12
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        // Icon view
        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFill
        iconView.layer.cornerRadius = 22
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Info stack
        let infoStack = UIStackView()
        infoStack.axis = .vertical
        infoStack.spacing = 2
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        // Advertiser label
        let advertiserLabel = UILabel()
        advertiserLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        advertiserLabel.textColor = .white
        advertiserLabel.translatesAutoresizingMaskIntoConstraints = false

        // Headline label
        let headlineLabel = UILabel()
        headlineLabel.font = UIFont.systemFont(ofSize: 12)
        headlineLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        headlineLabel.numberOfLines = 1
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        infoStack.addArrangedSubview(advertiserLabel)
        infoStack.addArrangedSubview(headlineLabel)

        // Ad badge (広告ラベル)
        let adBadgeLabel = UILabel()
        adBadgeLabel.text = "広告"
        adBadgeLabel.font = UIFont.systemFont(ofSize: 10)
        adBadgeLabel.textColor = .white
        adBadgeLabel.backgroundColor = UIColor.systemPurple
        adBadgeLabel.textAlignment = .center
        adBadgeLabel.layer.cornerRadius = 4
        adBadgeLabel.clipsToBounds = true
        adBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            adBadgeLabel.widthAnchor.constraint(equalToConstant: 32),
            adBadgeLabel.heightAnchor.constraint(equalToConstant: 18)
        ])

        headerStack.addArrangedSubview(iconView)
        headerStack.addArrangedSubview(infoStack)
        headerStack.addArrangedSubview(adBadgeLabel)

        // Media view
        let mediaView = MediaView()
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.setContentHuggingPriority(.defaultLow, for: .vertical)
        mediaView.setContentCompressionResistancePriority(.required, for: .vertical)

        // MediaViewに最小サイズ制約を追加（Google Adsの要件: 120x120以上）
        NSLayoutConstraint.activate([
            mediaView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            mediaView.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])

        // MediaViewにアスペクト比制約を追加（1:1の正方形）
        let aspectConstraint = mediaView.heightAnchor.constraint(equalTo: mediaView.widthAnchor, multiplier: 1.0)
        aspectConstraint.priority = .required
        aspectConstraint.isActive = true

        // Body stack
        let bodyStack = UIStackView()
        bodyStack.axis = .vertical
        bodyStack.spacing = 12
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        // Body label
        let bodyLabel = UILabel()
        bodyLabel.font = UIFont.systemFont(ofSize: 14)
        bodyLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        bodyLabel.numberOfLines = 3
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        // CTA button
        let ctaButton = UIButton(type: .system)
        ctaButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = .systemPurple
        ctaButton.layer.cornerRadius = 8
        ctaButton.isUserInteractionEnabled = false  // Google Ads SDKがクリックを処理
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ctaButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        bodyStack.addArrangedSubview(bodyLabel)
        bodyStack.addArrangedSubview(ctaButton)

        // Add padding views
        let headerContainer = UIView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            headerStack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -16)
        ])

        let bodyContainer = UIView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(bodyStack)
        NSLayoutConstraint.activate([
            bodyStack.topAnchor.constraint(equalTo: bodyContainer.topAnchor, constant: 16),
            bodyStack.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: 16),
            bodyStack.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -16),
            bodyStack.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -16)
        ])

        // Build container
        containerStack.addArrangedSubview(headerContainer)
        containerStack.addArrangedSubview(mediaView)
        containerStack.addArrangedSubview(bodyContainer)

        // AdViewに要素を追加
        adView.addSubview(containerStack)
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: adView.topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: adView.bottomAnchor)
        ])

        // AdChoices overlay（必須要件）
        let adChoicesView = AdChoicesView()
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(adChoicesView)

        let adChoicesSize: CGFloat = 15
        NSLayoutConstraint.activate([
            adChoicesView.topAnchor.constraint(equalTo: adView.topAnchor, constant: 8),
            adChoicesView.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -8),
            adChoicesView.widthAnchor.constraint(equalToConstant: adChoicesSize),
            adChoicesView.heightAnchor.constraint(equalToConstant: adChoicesSize)
        ])

        // Register ad view components
        adView.iconView = iconView
        adView.headlineView = headlineLabel
        adView.advertiserView = advertiserLabel
        adView.mediaView = mediaView
        adView.bodyView = bodyLabel
        adView.callToActionView = ctaButton
        adView.adChoicesView = adChoicesView

        // Populate content
        if let icon = nativeAd.icon?.image {
            iconView.image = icon
        } else {
            iconView.image = UIImage(systemName: "megaphone.fill")
            iconView.tintColor = .white
            iconView.backgroundColor = .gray.withAlphaComponent(0.3)
        }

        advertiserLabel.text = nativeAd.advertiser ?? "スポンサー"
        headlineLabel.text = nativeAd.headline
        bodyLabel.text = nativeAd.body

        if let callToAction = nativeAd.callToAction {
            ctaButton.setTitle(callToAction, for: .normal)
        }

        // Set the native ad (must be done after registering all components)
        adView.nativeAd = nativeAd

        // Force layout update
        adView.setNeedsLayout()
        adView.layoutIfNeeded()

        adView.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
        adView.layer.cornerRadius = 12
        adView.clipsToBounds = true

        return adView
    }

    func updateUIView(_ uiView: NativeAdView, context: Context) {
        // No need to update
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeAdView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width

        // 広告のコンテンツに基づいた高さを計算
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()

        let targetSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let size = uiView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        // 最小高さを保証（コンパクトな広告の場合）
        let minHeight: CGFloat = 350
        let finalHeight = max(size.height, minHeight)

        return CGSize(width: size.width, height: finalHeight)
    }
}
