//
//  BeaconDetector.swift
//  CoThings
//
//  Created by Neso on 2020/05/13.
//  Copyright © 2020 Rainlab. All rights reserved.
//

import Foundation
import CoreLocation
import Combine
#if DEBUG
import UserNotifications
#endif

struct BeaconIdentity: Hashable {
    let uuid: UUID
    let major: CLBeaconMajorValue
    let minor: CLBeaconMinorValue
}

extension Room {
    var beaconIdentity: BeaconIdentity? {
        guard let uuid = self.iBeaconUUID, let minor = self.minor, let major = self.major else { return nil }
        return BeaconIdentity(uuid: uuid,
                              major: CLBeaconMajorValue(major),
                              minor: CLBeaconMinorValue(minor))
    }
}

extension CLBeacon {
    var beaconIdentity: BeaconIdentity {
        return BeaconIdentity(uuid: self.uuid,
                              major: CLBeaconMajorValue(truncating: self.major),
                              minor: CLBeaconMinorValue(truncating: self.minor))
    }
}

struct Beacon {
    var proximity: CLProximity
    var strength: Int
    var accuracy: Double
    var constraint: CLBeaconIdentityConstraint
    var roomID: Room.ID
}

class BeaconDetector: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var beacons: [BeaconIdentity: Beacon] = [:]
    @Published private(set) var permissionGranted: Bool? = nil
    
    private(set) var enters = PassthroughSubject<Room.ID, Never>()
    private(set) var exits = PassthroughSubject<Room.ID, Never>()

	private var locationManager = CLLocationManager()

    override init() {
        super.init()

		locationManager.delegate = self
		locationManager.requestAlwaysAuthorization()
	}
    
    func startScanning(room: Room) {
        guard let beaconID = room.beaconIdentity,
            beacons[beaconID] == nil else { return }
        
        let constraint = CLBeaconIdentityConstraint(uuid: beaconID.uuid,
                                                    major: beaconID.major,
                                                    minor: beaconID.minor)

		let beaconRegion = CLBeaconRegion(uuid: beaconID.uuid, identifier: String(room.id))
		locationManager.startMonitoring(for: beaconRegion) // need it for start background monitoring

		locationManager.startRangingBeacons(satisfying: constraint)
        beacons[beaconID] = Beacon(proximity: .unknown,
                                   strength: 0,
                                   accuracy: 0,
                                   constraint: constraint,
                                   roomID: room.id)
    }
    
    func stopScanning(room: Room) {
        guard let beaconID = room.beaconIdentity,
            let beacon = beacons[beaconID] else { return }


		let beaconRegion = CLBeaconRegion(uuid: beaconID.uuid, identifier: String(room.id))
		locationManager.stopMonitoring(for: beaconRegion) // need it for stop background monitoring

        locationManager.stopRangingBeacons(satisfying: beacon.constraint)
        beacons.removeValue(forKey: beaconID)
    }

    // MARK: - CLLocationManager delegate
    internal func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            if CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) {
                permissionGranted = true
                return
            }
        }
        
        permissionGranted = false
    }

	internal func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
		#if DEBUG
		print("monitored region count:\(locationManager.monitoredRegions.count)")
		print("beacon count= \(beacons.count)")

		for beacon in beacons {
			let beaconID = beacon.beaconIdentity
			guard var oldBeacon = self.beacons[beaconID] else { continue }

//			let insideTheRoom = beacon.proximity == .near || beacon.proximity == .immediate
//			let wasInsideTheRoom =  oldBeacon.proximity == .near || oldBeacon.proximity == .immediate
//
//			if insideTheRoom && !wasInsideTheRoom {
//				enters.send(oldBeacon.roomID)
//			} else if wasInsideTheRoom && !insideTheRoom {
//				exits.send(oldBeacon.roomID)
//			}

			oldBeacon.proximity = beacon.proximity
			oldBeacon.strength = beacon.rssi
			oldBeacon.accuracy = beacon.accuracy
			self.beacons[beaconID] = oldBeacon
		}

		#endif

	}

	func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
		updateRoomStatus(for: region, isEntered: true)
	}

	func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
		updateRoomStatus(for: region, isEntered: false)
	}

	func updateRoomStatus(for region: CLRegion, isEntered: Bool) {
		guard region is CLBeaconRegion else { return }
		let beaconRegion = region as? CLBeaconRegion

		guard let beaconIdentifier = beaconRegion?.identifier else { return }
		let roomId = Int(beaconIdentifier)

		var status: [String: Bool] = UserDefaults.standard.object(forKey: RoomStatusesKey) as? [String : Bool] ?? [ : ]

		if status[beaconIdentifier] != isEntered {
			status[beaconIdentifier] = isEntered
			UserDefaults.standard.set(status, forKey: RoomStatusesKey)
			if (isEntered) {
				enters.send(roomId!)
			} else {
				exits.send(roomId!)
			}
		}

		#if DEBUG
		print("monitored region count:\(locationManager.monitoredRegions.count)")
		push(roomId: roomId!, isEntered: isEntered)
		#endif
	}

	internal func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
		print("Failed monitoring region: \(error.localizedDescription)")
	}

	internal func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		print("Location manager failed: \(error.localizedDescription)")
	}

	#if DEBUG
	func push(roomId: Int, isEntered: Bool) {
		let content = UNMutableNotificationContent()

		let action = isEntered ? "Enter" : "Exit"

		content.title = "CoThings Room: \(roomId)"
		content.body = "Action:\(action) beacon count:\(self.beacons.count)"
		content.sound = .default

		let request = UNNotificationRequest(identifier: "testNotification" + String(Int.random(in: 200...300)),
											content: content,
											trigger: nil)

		let userNotificationCenter = UNUserNotificationCenter.current()
		userNotificationCenter.add(request)

	}
	#endif
}
