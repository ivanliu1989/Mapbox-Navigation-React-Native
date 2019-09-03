import XCTest
#if !SWIFT_PACKAGE
import OHHTTPStubs
import Polyline
@testable import MapboxDirections

class V5Tests: XCTestCase {
    override func tearDown() {
        OHHTTPStubs.removeAllStubs()
        super.tearDown()
    }
    
    typealias JSONTransformer = ((JSONDictionary) -> JSONDictionary)
    
    func test(shapeFormat: RouteShapeFormat, transformer: JSONTransformer? = nil, filePath: String? = nil) {
        let expectation = self.expectation(description: "calculating directions should return results")
        
        let queryParams: [String: String?] = [
            "alternatives": "true",
            "geometries": String(describing: shapeFormat),
            "overview": "full",
            "steps": "true",
            "continue_straight": "true",
            "access_token": BogusToken,
        ]
        stub(condition: isHost("api.mapbox.com")
            && isPath("/directions/v5/mapbox/driving/-122.42,37.78;-77.03,38.91.json")
            && containsQueryParams(queryParams)) { _ in
                let path = Bundle(for: type(of: self)).path(forResource: filePath ?? "v5_driving_dc_\(shapeFormat)", ofType: "json")
                let filePath = URL(fileURLWithPath: path!)
                let data = try! Data(contentsOf: filePath, options: [])
                let jsonObject = try! JSONSerialization.jsonObject(with: data, options: [])
                let transformedData = transformer?(jsonObject as! JSONDictionary) ?? jsonObject
                return OHHTTPStubsResponse(jsonObject: transformedData, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        let options = RouteOptions(coordinates: [
            CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42),
            CLLocationCoordinate2D(latitude: 38.91, longitude: -77.03),
        ])
        XCTAssertEqual(options.shapeFormat, .polyline, "Route shape format should be Polyline by default.")
        options.shapeFormat = shapeFormat
        options.includesSteps = true
        options.includesAlternativeRoutes = true
        options.routeShapeResolution = .full
        options.includesVisualInstructions = true
        options.includesSpokenInstructions = true
        options.locale = Locale(identifier: "en_US")
        options.includesExitRoundaboutManeuver = true
        var route: Route?
        let task = Directions(accessToken: BogusToken).calculate(options) { (waypoints, routes, error) in
            XCTAssertNil(error, "Error: \(error!)")
            
            XCTAssertEqual(waypoints?.count, 2)
            
            XCTAssertNotNil(routes)
            XCTAssertEqual(routes!.count, 2)
            route = routes!.first!
            
            expectation.fulfill()
        }
        XCTAssertNotNil(task)
        
        waitForExpectations(timeout: 5) { (error) in
            XCTAssertNil(error, "Error: \(error!)")
            XCTAssertEqual(task.state, .completed)
        }
        
        test(route, options: options)
    }
    
    func test(_ route: Route?, options: RouteOptions) {
        XCTAssertNotNil(route)
        guard let route = route else {
            return
        }
        
        XCTAssertNotNil(route.coordinates)
        XCTAssertEqual(route.coordinates?.count, 30_097)
        XCTAssertEqual(route.accessToken, BogusToken)
        XCTAssertEqual(route.apiEndpoint, URL(string: "https://api.mapbox.com"))
        XCTAssertEqual(route.routeIdentifier?.count, 25)
        XCTAssertTrue(route.routeIdentifier?.starts(with: "cjsb5x") ?? false)
        XCTAssertEqual(route.speechLocale?.identifier, "en-US")
        
        // confirming actual decoded values is important because the Directions API
        // uses an atypical precision level for polyline encoding
        XCTAssertEqual(route.coordinates?.first?.latitude ?? 0, 38, accuracy: 1)
        XCTAssertEqual(route.coordinates?.first?.longitude ?? 0, -122, accuracy: 1)
        XCTAssertEqual(route.legs.count, 1)
        
        let opts = route.routeOptions
        XCTAssertEqual(opts, options)
        
        XCTAssertEqual(route.legs.count, 1)
        let leg = route.legs.first
        XCTAssertEqual(leg?.name, "Dwight D. Eisenhower Highway, I-80")
        XCTAssertEqual(leg?.steps.count, 59)
        
        // The Carquinez Bridge is tolled.
        let tolledStep = leg?.steps[5]
        let tolledStepIntersections = tolledStep?.intersections
        XCTAssertNotNil(tolledStepIntersections)
        let tolledIntersection = tolledStepIntersections?[38]
        let roadClasses = tolledIntersection?.outletRoadClasses
        XCTAssertNotNil(roadClasses)
        XCTAssertEqual(roadClasses, [.toll, .motorway])
        
        let step = leg?.steps[48]
        XCTAssertEqual(step?.distance ?? 0, 621, accuracy: 1)
        XCTAssertEqual(step?.expectedTravelTime ?? 0, 31, accuracy: 1)
        XCTAssertEqual(step?.instructions, "Take exit 43-44 towards VA 193: George Washington Memorial Parkway")
        
        XCTAssertNil(step?.names)
        XCTAssertEqual(step?.destinationCodes, ["VA 193"])
        XCTAssertEqual(step?.destinations, ["George Washington Memorial Parkway", "Washington", "Georgetown Pike"])
        XCTAssertEqual(step?.maneuverType, .takeOffRamp)
        XCTAssertEqual(step?.maneuverDirection, .slightRight)
        XCTAssertEqual(step?.initialHeading, 192)
        XCTAssertEqual(step?.finalHeading, 202)
        
        XCTAssertNotNil(step?.coordinates)
        XCTAssertEqual(step?.coordinates?.count, 13)
        XCTAssertEqual(step?.coordinates?.count, Int(step?.coordinateCount ?? 0))
        XCTAssertEqual(step?.coordinates?.first?.latitude ?? 0, 38.9667, accuracy: 1e-4)
        XCTAssertEqual(step?.coordinates?.first?.longitude ?? 0, -77.1802, accuracy: 1e-4)
        
        XCTAssertNil(leg?.steps[32].names)
        XCTAssertEqual(leg?.steps[32].codes, ["I-80"])
        XCTAssertEqual(leg?.steps[32].destinationCodes, ["I-80 East", "I-90"])
        XCTAssertEqual(leg?.steps[32].destinations, ["Toll Road"])
        
        XCTAssertEqual(leg?.steps[35].names, ["Ohio Turnpike"])
        XCTAssertEqual(leg?.steps[35].codes, ["I-80 East"])
        XCTAssertNil(leg?.steps[35].destinationCodes)
        XCTAssertNil(leg?.steps[35].destinations)
        
        let intersections = leg?.steps[4].intersections
        XCTAssertNotNil(intersections)
        XCTAssertEqual(intersections?.count, 29)
        let intersection = intersections?[0]
        XCTAssertEqual(intersection?.outletIndexes, IndexSet([0, 1]))
        XCTAssertEqual(intersection?.approachIndex, 2)
        XCTAssertEqual(intersection?.outletIndex, 0)
        XCTAssertEqual(intersection?.headings, [105, 135, 285])
        XCTAssertEqual(intersection?.location.latitude ?? 0, 37.7691, accuracy: 1e-4)
        XCTAssertEqual(intersection?.location.longitude ?? 0, -122.4092, accuracy: 1e-4)
        XCTAssertEqual(intersection?.usableApproachLanes, IndexSet([0, 1]))
        XCTAssertNotNil(intersection?.approachLanes)
        XCTAssertEqual(intersection?.approachLanes?.count, 3)
        XCTAssertEqual(intersection?.approachLanes?[1].indications, [.slightLeft, .slightRight])
        
        XCTAssertEqual(leg?.steps[58].names, ["Logan Circle Northwest"])
        XCTAssertNil(leg?.steps[58].exitNames)
        XCTAssertNil(leg?.steps[58].codes)
        XCTAssertNil(leg?.steps[58].destinationCodes)
        XCTAssertNil(leg?.steps[58].destinations)
    }
    
    func testGeoJSON() {
        XCTAssertEqual(String(describing: RouteShapeFormat.geoJSON), "geojson")
        test(shapeFormat: .geoJSON)
    }
    
    func testPolyline() {
        XCTAssertEqual(String(describing: RouteShapeFormat.polyline), "polyline")
        test(shapeFormat: .polyline)
    }
    
    func testPolyline6() {
        XCTAssertEqual(String(describing: RouteShapeFormat.polyline6), "polyline6")
        
        // Transform polyline5 to polyline6
        let transformer: JSONTransformer = { json in
            var transformed = json
            var route = (transformed["routes"] as! [JSONDictionary])[0]
            let polyline = route["geometry"] as! String
            
            let decodedCoordinates: [CLLocationCoordinate2D] = decodePolyline(polyline, precision: 1e5)!
            route["geometry"] = Polyline(coordinates: decodedCoordinates, levels: nil, precision: 1e6).encodedPolyline
            
            let legs = route["legs"] as! [JSONDictionary]
            var newLegs = [JSONDictionary]()
            for var leg in legs {
                let steps = leg["steps"] as! [JSONDictionary]
                
                var newSteps = [JSONDictionary]()
                for var step in steps {
                    let geometry = step["geometry"] as! String
                    let coords: [CLLocationCoordinate2D] = decodePolyline(geometry, precision: 1e5)!
                    step["geometry"] = Polyline(coordinates: coords, precision: 1e6).encodedPolyline
                    newSteps.append(step)
                }
                
                leg["steps"] = newSteps
                newLegs.append(leg)
            }
            
            route["legs"] = newLegs
            
            let secondRoute = (json["routes"] as! [JSONDictionary])[1]
            transformed["routes"] = [route, secondRoute]
            
            return transformed
        }
        
        test(shapeFormat: .polyline6, transformer: transformer, filePath: "v5_driving_dc_polyline")
    }
    
    func testViaPoints() {
        let expectation = self.expectation(description: "calculating directions should return results")
        
        let queryParams: [String: String?] = [
            "geometries": "polyline",
            "overview": "full",
            "steps": "true",
            "language": "de_US",
            "waypoints": "0;2",
            "waypoint_names": "From;To",
            "alternatives": "false",
            "continue_straight": "true",
            "roundabout_exits": "true",
            "access_token": BogusToken,
        ]
        stub(condition: isHost("api.mapbox.com")
            && isPath("/directions/v5/mapbox/driving/-85.206232,39.33841;-85.203991,39.34181;-85.199697,39.342048.json")
            && containsQueryParams(queryParams)) { _ in
                let path = Bundle(for: type(of: self)).path(forResource: "v5_driving_oldenburg_polyline", ofType: "json")
                let filePath = URL(fileURLWithPath: path!)
                let data = try! Data(contentsOf: filePath, options: [])
                let jsonObject = try! JSONSerialization.jsonObject(with: data, options: [])
                return OHHTTPStubsResponse(jsonObject: jsonObject, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        let waypoints = [
            Waypoint(coordinate: CLLocationCoordinate2D(latitude: 39.33841036211459, longitude: -85.20623174166413), coordinateAccuracy: -1, name: "From"),
            Waypoint(coordinate: CLLocationCoordinate2D(latitude: 39.34181048315713, longitude: -85.20399062653789), coordinateAccuracy: -1, name: "Via"),
            Waypoint(coordinate: CLLocationCoordinate2D(latitude: 39.34204769474999, longitude: -85.19969651878529), coordinateAccuracy: -1, name: "To"),
        ]
        for waypoint in waypoints {
            waypoint.separatesLegs = false
        }
        
        let options = RouteOptions(waypoints: waypoints)
        XCTAssertEqual(options.shapeFormat, .polyline, "Route shape format should be Polyline by default.")
        options.shapeFormat = .polyline
        options.includesSteps = true
        options.routeShapeResolution = .full
        options.locale = Locale(identifier: "de_US")
        options.includesExitRoundaboutManeuver = true
        
        var route: Route?
        let task = Directions(accessToken: BogusToken).calculate(options) { (waypoints, routes, error) in
            XCTAssertNil(error, "Error: \(error!)")
            
            XCTAssertEqual(waypoints?.count, 3)
            
            XCTAssertNotNil(routes)
            XCTAssertEqual(routes!.count, 1)
            route = routes!.first!
            
            expectation.fulfill()
        }
        XCTAssertNotNil(task)
        
        waitForExpectations(timeout: 2) { (error) in
            XCTAssertNil(error, "Error: \(error!)")
            XCTAssertEqual(task.state, .completed)
        }
        
        XCTAssertEqual(route?.legs.count, 1)
        let leg = route?.legs.first
        XCTAssertEqual(leg?.source.name, waypoints[0].name)
        XCTAssertEqual(leg?.source.coordinate.latitude ?? 0, waypoints[0].coordinate.latitude, accuracy: 1e-4)
        XCTAssertEqual(leg?.source.coordinate.longitude ?? 0, waypoints[0].coordinate.longitude, accuracy: 1e-4)
        XCTAssertEqual(leg?.destination.name, waypoints[2].name)
        XCTAssertEqual(leg?.destination.coordinate.latitude ?? 0, waypoints[2].coordinate.latitude, accuracy: 1e-4)
        XCTAssertEqual(leg?.destination.coordinate.longitude ?? 0, waypoints[2].coordinate.longitude, accuracy: 1e-4)
        XCTAssertEqual(leg?.name, "Perlen Strasse, Haupt Strasse")
    }
    
    func testCoding() {
        let path = Bundle(for: type(of: self)).path(forResource: "v5_driving_dc_polyline", ofType: "json")
        let filePath = URL(fileURLWithPath: path!)
        let data = try! Data(contentsOf: filePath, options: [])
        let jsonResponse = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
        
        let options = RouteOptions(coordinates: [
            CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42),
            CLLocationCoordinate2D(latitude: 38.91, longitude: -77.03),
        ])
        let routes = options.response(from: jsonResponse).1
        let route = routes!.first!
        route.accessToken = BogusToken
        route.apiEndpoint = URL(string: "https://api.mapbox.com")
        route.routeIdentifier = jsonResponse["uuid"] as? String
        
        // Encode and decode the route securely.
        // This may raise an Objective-C exception if an error occurs, which will fail the tests.
        
        let encodedData = NSMutableData()
        let keyedArchiver = NSKeyedArchiver(forWritingWith: encodedData)
        keyedArchiver.requiresSecureCoding = true
        keyedArchiver.encode(route, forKey: "route")
        keyedArchiver.finishEncoding()
        
        let keyedUnarchiver = NSKeyedUnarchiver(forReadingWith: encodedData as Data)
        keyedUnarchiver.requiresSecureCoding = true
        let unarchivedRoute = keyedUnarchiver.decodeObject(of: Route.self, forKey: "route")!
        keyedUnarchiver.finishDecoding()
        
        test(unarchivedRoute, options: options)
    }
}
#endif
