//
//  NotarizationResponse.swift
//  dmgdist
//
//  Created by Gui Rambo on 08/10/20.
//

import Foundation

struct NotarizationResponse: Hashable, Decodable {
    let upload: Upload

    struct Upload: Hashable, Decodable {
        let requestUUID: String

        enum CodingKeys: String, CodingKey {
            case requestUUID = "RequestUUID"
        }
    }

    enum CodingKeys: String, CodingKey {
        case upload = "notarization-upload"
    }
}
