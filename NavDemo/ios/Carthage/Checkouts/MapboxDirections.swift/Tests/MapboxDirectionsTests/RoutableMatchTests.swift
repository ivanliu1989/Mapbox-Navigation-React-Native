import XCTest
#if !SWIFT_PACKAGE
import OHHTTPStubs
@testable import MapboxDirections

class RoutableMatchTest: XCTestCase {
    override func tearDown() {
        OHHTTPStubs.removeAllStubs()
        super.tearDown()
    }
    
    func testRoutableMatch() {
        let expectation = self.expectation(description: "calculating directions should return results")
        let locations = [CLLocationCoordinate2D(latitude: 32.712041, longitude: -117.172836),
                         CLLocationCoordinate2D(latitude: 32.712256, longitude: -117.17291),
                         CLLocationCoordinate2D(latitude: 32.712444, longitude: -117.17292),
                         CLLocationCoordinate2D(latitude: 32.71257, longitude: -117.172922),
                         CLLocationCoordinate2D(latitude: 32.7126, longitude: -117.172985),
                         CLLocationCoordinate2D(latitude: 32.712597, longitude: -117.173143),
                         CLLocationCoordinate2D(latitude: 32.712546, longitude: -117.173345)]
        
        stub(condition: isHost("api.mapbox.com")
            && isMethodGET()
            && pathStartsWith("/matching/v5/mapbox/driving")) { _ in
                let path = Bundle(for: type(of: self)).path(forResource: "match", ofType: "json")
                return OHHTTPStubsResponse(fileAtPath: path!, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        var route: Route!
        var waypoints: [Waypoint]!
        
        let matchOptions = MatchOptions(coordinates: locations)
        matchOptions.includesSteps = true
        matchOptions.routeShapeResolution = .full
        for waypoint in matchOptions.waypoints[1..<(locations.count - 1)] {
            waypoint.separatesLegs = false
        }
        
        
        let task = Directions(accessToken: BogusToken).calculateRoutes(matching: matchOptions) { (wpoints, routes, error) in
            XCTAssertNil(error, "Error: \(error!)")
            
            route = routes!.first!
            waypoints = wpoints
            
            expectation.fulfill()
        }
        XCTAssertNotNil(task)
        
        waitForExpectations(timeout: 2) { (error) in
            XCTAssertNil(error, "Error: \(error!)")
            XCTAssertEqual(task.state, .completed)
        }
        
        XCTAssertNotNil(route)
        XCTAssertNotNil(route.coordinates)
        XCTAssertEqual(route.coordinates!.count, 8)
        XCTAssertEqual(route.accessToken, BogusToken)
        XCTAssertEqual(route.apiEndpoint, URL(string: "https://api.mapbox.com"))
        XCTAssertEqual(route.routeIdentifier, nil)
        
        XCTAssertNotNil(waypoints)
        XCTAssertEqual(waypoints.first!.name, "North Harbor Drive")
        XCTAssertEqual(waypoints.last!.name, "West G Street")
        XCTAssertNotNil(waypoints.last!.coordinate)
        
        // confirming actual decoded values is important because the Directions API
        // uses an atypical precision level for polyline encoding
        XCTAssertEqual(round(route!.coordinates!.first!.latitude), 33)
        XCTAssertEqual(round(route!.coordinates!.first!.longitude), -117)
        XCTAssertEqual(route!.legs.count, 1)
        
        let leg = route!.legs.first!
        XCTAssertEqual(leg.name, "North Harbor Drive")
        XCTAssertEqual(leg.steps.count, 2)
        
        let firstStep = leg.steps.first
        XCTAssertNotNil(firstStep)
        let firstStepIntersections = firstStep?.intersections
        XCTAssertNotNil(firstStepIntersections)
        let firstIntersection = firstStepIntersections?.first
        XCTAssertNotNil(firstIntersection)
        
        let step = leg.steps[0]
        XCTAssertEqual(round(step.distance), 25)
        XCTAssertEqual(round(step.expectedTravelTime), 3)
        XCTAssertEqual(step.instructions, "Head north on North Harbor Drive")
        
        XCTAssertEqual(step.maneuverType, .depart)
        XCTAssertEqual(step.maneuverDirection, .none)
        XCTAssertEqual(step.initialHeading, 0)
        XCTAssertEqual(step.finalHeading, 340)
        
        XCTAssertNotNil(step.coordinates)
        XCTAssertEqual(step.coordinates!.count, 4)
        XCTAssertEqual(step.coordinates!.count, Int(step.coordinateCount))
        let coordinate = step.coordinates!.first!
        XCTAssertEqual(round(coordinate.latitude), 33)
        XCTAssertEqual(round(coordinate.longitude), -117)
    }
}
#endif
