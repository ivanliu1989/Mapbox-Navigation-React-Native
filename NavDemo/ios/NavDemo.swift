//
//  NavDemo.swift
//  NavDemo
//
//  Created by Tianxiang Liu on 2/9/19.
//  Copyright © 2019 Facebook. All rights reserved.
//

import Foundation
import MapboxDirections
import MapboxCoreNavigation
import MapboxNavigation

@objc(NavDemo)
class NavDemo: NSObject {
 
  @objc
  func renderNaviDemo(_ originLat: NSNumber, oriLon originLon: NSNumber, oriName originName: NSString, destLat destinationLat: NSNumber, destLon destinationLon: NSNumber, destName destinationName: NSString) {
    
    let origin = Waypoint(coordinate: CLLocationCoordinate2D(latitude: CLLocationDegrees(truncating: originLat), longitude: CLLocationDegrees(truncating: originLon)), name: originName as String)
    let destination = Waypoint(coordinate: CLLocationCoordinate2D(latitude: CLLocationDegrees(truncating: destinationLat), longitude: CLLocationDegrees(truncating: destinationLon)), name: destinationName as String)
    
    let options = NavigationRouteOptions(waypoints: [origin, destination])
    
    Directions.shared.calculate(options) { (waypoints, routes, error) in
      guard let route = routes?.first else { return }
      
      let viewController = NavigationViewController(for: route)
      let appDelegate = UIApplication.shared.delegate
      appDelegate!.window!!.rootViewController!.present(viewController, animated: true, completion: nil)
    }
  }
}
