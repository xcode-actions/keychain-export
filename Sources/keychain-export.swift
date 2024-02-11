import Foundation
import Security

import ArgumentParser



@main
struct KeychainExport : AsyncParsableCommand {
	
//	@Option
//	var entityType: EntityType = .certificate
	
	@Argument
	var entityName: String
	
	func run() async throws {
		let certificate = try findCertificate(named: entityName)
		let identity = try findIdentity(matching: certificate)
		
		let certificateData = try {
			let alertTitle = "BEWARE!" as CFString
			let alertPrompt = "You’re exporting a private key, you fool." as CFString
			var keyParams = SecItemImportExportKeyParameters(
				version: UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION),
				flags: [/*.securePassphrase*/],
				passphrase: nil,
				alertTitle: Unmanaged.passUnretained(alertTitle),
				alertPrompt: Unmanaged.passUnretained(alertPrompt),
				accessRef: nil, keyUsage: nil, keyAttributes: nil
			)
			var res: CFData?
			let err = SecItemExport(certificate, .formatX509Cert, .pemArmour, &keyParams, &res)
			guard err == noErr else {throw Self.secErrorFrom(statusCode: err)}
			return res! as Data
			/* The following does not work.
			 * There might be a way to make it work, but I don’t know it. */
//			var error: Unmanaged<CFError>?
//			guard let data = SecKeyCopyExternalRepresentation(privateKey, &error) else {
//				throw SimpleError("Failed copying private key content: \((error?.takeUnretainedValue()).flatMap{ "\($0)" } ?? "Unknown error").")
//			}
//			return data as NSData
		}()
		guard let certificateString = String(data: certificateData, encoding: .ascii) else {
			throw SimpleError("Cannot read certificate data as PEM.")
		}
		
		let privateKey = try {
			var res: SecKey?
			let err = SecIdentityCopyPrivateKey(identity, &res)
			guard err == noErr else {throw Self.secErrorFrom(statusCode: err)}
			return res!
		}()
		let privateKeyData = try {
			let password = "toto" as CFTypeRef
			let alertTitle = "BEWARE!" as CFString
			let alertPrompt = "You’re exporting a private key, you fool." as CFString
			var keyParams = SecItemImportExportKeyParameters(
				version: UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION),
				flags: [/*.securePassphrase*/],
				passphrase: Unmanaged.passUnretained(password),
				alertTitle: Unmanaged.passUnretained(alertTitle),
				alertPrompt: Unmanaged.passUnretained(alertPrompt),
				accessRef: nil, keyUsage: nil, keyAttributes: nil
			)
			var res: CFData?
			let err = SecItemExport(privateKey, .formatWrappedPKCS8, .pemArmour, &keyParams, &res)
			guard err == noErr else {throw Self.secErrorFrom(statusCode: err)}
			return res! as Data
			/* The following does not work.
			 * There might be a way to make it work, but I don’t know it. */
//			var error: Unmanaged<CFError>?
//			guard let data = SecKeyCopyExternalRepresentation(privateKey, &error) else {
//				throw SimpleError("Failed copying private key content: \((error?.takeUnretainedValue()).flatMap{ "\($0)" } ?? "Unknown error").")
//			}
//			return data as NSData
		}()
		
		guard let privateKeyString = String(data: privateKeyData, encoding: .ascii) else {
			throw SimpleError("Cannot read private key data as PEM.")
		}
		print(certificateString)
		print(privateKeyString)
	}
	
	private func findIdentity(matching certificate: SecCertificate) throws -> SecIdentity {
		var query = [String: Any]()
		query[kSecClass               as String] = kSecClassIdentity
		query[kSecMatchItemList       as String] = [certificate] as CFArray
		query[kSecMatchLimit          as String] = kSecMatchLimitAll
		query[kSecReturnData          as String] = kCFBooleanFalse
		query[kSecReturnRef           as String] = kCFBooleanTrue
		query[kSecReturnPersistentRef as String] = kCFBooleanFalse
		query[kSecReturnAttributes    as String] = kCFBooleanFalse
		
		var searchResult: CFTypeRef?
		let error = SecItemCopyMatching(query as CFDictionary, &searchResult)
		switch error {
			case errSecSuccess:
				guard CFGetTypeID(searchResult) == CFArrayGetTypeID() else {
					throw SimpleError("Result does not have the expected type.")
				}
				let resultArray = searchResult as! [CFTypeRef]
				let c = resultArray.count
				guard c == 1 else {
					throw SimpleError("Got \(c) results; expected only 1.")
				}
				let firstResult = resultArray[0]
				guard CFGetTypeID(firstResult) == SecIdentityGetTypeID() else {
					throw SimpleError("Result does not have the expected type.")
				}
				return firstResult as! SecIdentity
				
			case errSecItemNotFound:
				throw SimpleError("No certificate with the given name.")
				
			default:
				throw Self.secErrorFrom(statusCode: error)
		}
	}
	
	private func findCertificate(named: String) throws -> SecCertificate {
		var query = [String: Any]()
		query[kSecClass               as String] = kSecClassCertificate
		query[kSecAttrLabel           as String] = entityName
		query[kSecMatchLimit          as String] = kSecMatchLimitAll
		query[kSecReturnData          as String] = kCFBooleanFalse
		query[kSecReturnRef           as String] = kCFBooleanTrue
		query[kSecReturnPersistentRef as String] = kCFBooleanFalse
		query[kSecReturnAttributes    as String] = kCFBooleanFalse
		
		var searchResult: CFTypeRef?
		let error = SecItemCopyMatching(query as CFDictionary, &searchResult)
		switch error {
			case errSecSuccess:
				guard CFGetTypeID(searchResult) == CFArrayGetTypeID() else {
					throw SimpleError("Result does not have the expected type.")
				}
				let resultArray = searchResult as! [CFTypeRef]
				let c = resultArray.count
				guard c == 1 else {
					throw SimpleError("Got \(c) results; expected only 1.")
				}
				let firstResult = resultArray[0]
				guard CFGetTypeID(firstResult) == SecCertificateGetTypeID() else {
					throw SimpleError("Result does not have the expected type.")
				}
				return firstResult as! SecCertificate
				
			case errSecItemNotFound:
				throw SimpleError("No certificate with the given name.")
				
			default:
				throw Self.secErrorFrom(statusCode: error)
		}
	}
	
	private static func secErrorFrom(statusCode: OSStatus) -> SimpleError {
#if os(macOS)
		return SimpleError("Security framework failure \(statusCode): \(SecCopyErrorMessageString(statusCode, nil /* reserved for future use */) as String?).")
#else
		return SimpleError("Security framework failure \(statusCode)")
#endif
	}
	
}


struct SimpleError : Error {
	
	var message: String
	init(_ message: String) {
		self.message = message
	}
	
}
