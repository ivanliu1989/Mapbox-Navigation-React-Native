import XCTest
#if !SWIFT_PACKAGE
import OHHTTPStubs
@testable import MapboxDirections


class OfflineDirectionsTests: XCTestCase {
    
    let token = "foo"
    let host = "api.mapbox.com"
    
    func testAvailableVersions() {
        let directions = Directions(accessToken: token, host: host)
        
        XCTAssertEqual(directions.accessToken, token)
        
        let versionsExpectation = expectation(description: "Fetching available versions should return results")
        
        let apiStub = stub(condition: isHost(host)) { _ in
            let bundle = Bundle(for: type(of: self))
            let path = bundle.path(forResource: "versions", ofType: "json")
            let filePath = URL(fileURLWithPath: path!)
            let data = try! Data(contentsOf: filePath)
            let jsonObject = try! JSONSerialization.jsonObject(with: data, options: [])
            return OHHTTPStubsResponse(jsonObject: jsonObject, statusCode: 200, headers: ["Content-Type": "application/json"])
        }
        
        directions.fetchAvailableOfflineVersions { (versions, error) in
            XCTAssertEqual(versions!.count, 1)
            XCTAssertEqual(versions!.first!, "2018-10-16")
            
            versionsExpectation.fulfill()
            OHHTTPStubs.removeStub(apiStub)
        }
        
        wait(for: [versionsExpectation], timeout: 2)
    }
    
    func testCoordinateBounds() {
        let bounds = CoordinateBounds(coordinates: [CLLocationCoordinate2D(latitude: 37.7890, longitude: -122.4337),
                                                    CLLocationCoordinate2D(latitude: 37.7881, longitude: -122.4318)])
        XCTAssertEqual(bounds.southWest.latitude, 37.7881)
        XCTAssertEqual(bounds.southWest.longitude, -122.4337)
        XCTAssertEqual(bounds.northEast.latitude, 37.7890)
        XCTAssertEqual(bounds.northEast.longitude, -122.4318)
        XCTAssertEqual(bounds.description, "-122.4337,37.7881;-122.4318,37.789")
    }

    func testDownloadTiles() {
        
        let directions = Directions(accessToken: token, host: host)

        let bounds = CoordinateBounds(coordinates: [CLLocationCoordinate2D(latitude: 37.7890, longitude: -122.4337),
                                                    CLLocationCoordinate2D(latitude: 37.7881, longitude: -122.4318)])
        
        let version = "2018-10-16"
        let downloadExpectation = self.expectation(description: "Download tile expectation")
        
        let apiStub = stub(condition: isHost(host)) { _ in
            let bundle = Bundle(for: type(of: self))
            let path = bundle.path(forResource: "2018-10-16-Liechtenstein", ofType: "tar")

            let attributes = try! FileManager.default.attributesOfItem(atPath: path!)
            let fileSize = attributes[.size] as! UInt64
            
            var headers = [AnyHashable: Any]()
            headers["Content-Type"] = "application/gzip"
            headers["Content-Length"] = "\(fileSize)"
            headers["Accept-Ranges"] = "bytes"
            headers["Content-Disposition"] = "attachment; filename=\"\(version).tar\""
            
            return OHHTTPStubsResponse(fileAtPath: path!, statusCode: 200, headers: headers)
        }
        
        directions.downloadTiles(in: bounds, version: version, completionHandler: { (url, response, error) in
            XCTAssertEqual(response!.suggestedFilename, "2018-10-16.tar")
            XCTAssertNotNil(url, "url should point to the temporary local file")
            XCTAssertNil(error)
            
            downloadExpectation.fulfill()
            OHHTTPStubs.removeStub(apiStub)
        })
        
        wait(for: [downloadExpectation], timeout: 60)
    }
}
#endif
