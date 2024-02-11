import Foundation
import Security
import System

import ArgumentParser
import COpenSSL
import StreamReader
import UnwrapOrThrow



@main
struct KeychainExport : AsyncParsableCommand {
	
	static let dummyPassword = "toto"
	
//	@Option
//	var entityType: EntityType = .certificate
	
	@Argument
	var entityName: String
	
	func run() async throws {
		let certificate = try findCertificate(named: entityName)
		let identity = try findIdentity(matching: certificate)
		
		let certificateData = try {
			let alertTitle = "Certificate Export" as CFString
			let alertPrompt = "Give us your password; we needs it to export the certificate!" as CFString
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
			let password = Self.dummyPassword as CFTypeRef
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
		
		/* Use OpenSSL to export the unencrypted private key. */
		let b = try BIO_new(BIO_s_mem() ?! SimpleError("Cannot allocation BIO mem.")) ?! SimpleError("Cannot create a BIO.")
		defer {BIO_free(b)}
		guard (privateKeyData.withUnsafeBytes{ bytes in BIO_write(b, bytes.baseAddress!, Int32(bytes.count)) }) == privateKeyData.count else {
			throw SimpleError("Failed to write all the data to BIO.")
		}
		var password = Self.dummyPassword.utf8CString
		guard let pkey = (password.withUnsafeMutableBytes{ bytes in PEM_read_bio_PrivateKey(b, nil, nil, bytes.baseAddress!) }) else {
			throw SimpleError("Cannot read PEM from BIO.")
		}
		defer {EVP_PKEY_free(pkey)}
		let bo = try BIO_new(BIO_s_mem() ?! SimpleError("Cannot allocation BIO mem.")) ?! SimpleError("Cannot create a BIO.")
		defer {BIO_free(bo)}
		guard PEM_write_bio_PKCS8PrivateKey(bo, pkey, nil, nil, 0, nil, nil) != 0 else {
			throw SimpleError("Cannot write PEM to BIO.")
		}
		let reader = GenericStreamReader(stream: OpenSSLBio(bio: bo), bufferSize: 1024, bufferSizeIncrement: 512)
		let decodedPrivateKeyData = try reader.readDataToEnd()
		let decodedPrivateKeyString = try String(data: decodedPrivateKeyData, encoding: .ascii) ?! SimpleError("Cannot decode decoded pkey as ascii String.")
		
		print(certificateString)
		print(decodedPrivateKeyString)
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


private class IntRef {
	
	var value: Int
	
	init(_ value: Int) {
		self.value = value
	}
	
}


private class OpenSSLBio : GenericReadStream {
	
	var bio: OpaquePointer!
	
	init(bio: OpaquePointer!) {
		self.bio = bio
	}
	
	func read(_ buffer: UnsafeMutableRawPointer, maxLength len: Int) throws -> Int {
		var res = Int(0)
		guard BIO_ctrl(bio, BIO_CTRL_EOF, 0, nil) == 0 else {
			return 0
		}
		guard BIO_read_ex(bio, buffer, len, &res) != 0 else {
			throw SimpleError("Failed reading from BIO.")
		}
		return res
	}
	
}
