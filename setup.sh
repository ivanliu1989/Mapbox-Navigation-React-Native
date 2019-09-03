export RNAPP=NavDemo
export RN_VERSION=0.60.5
react-native init $RNAPP --version $RN_VERSION
cd $RNAPP
npm install --save
cd ios/
pod init
pod repo update && pod install

# Install Mapbox Navigation SDK using Cathage
echo 'github "mapbox/mapbox-navigation-ios" ~> 0.36' > Cartfile
carthage update --platform iOS

# vim input.xcfilelist
# vim output.xcfilelist
