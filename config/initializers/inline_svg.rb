# inline_svg needs the Propshaft finder since this app uses Propshaft (not Sprockets).
InlineSvg.configure do |config|
  config.asset_finder = InlineSvg::PropshaftAssetFinder
end
