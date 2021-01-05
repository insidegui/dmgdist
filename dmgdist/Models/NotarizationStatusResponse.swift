//
//  NotarizationStatusResponse.swift
//  dmgdist
//
//  Created by Gui Rambo on 08/10/20.
//

import Foundation

struct NotarizationStatusResponse: Hashable, Decodable {

    let info: Info?

    struct Info: Hashable, Decodable {
        let status: String
        let statusMessage: String?

        enum CodingKeys: String, CodingKey {
            case status = "Status"
            case statusMessage = "Status Message"
        }
    }

    enum CodingKeys: String, CodingKey {
        case info = "notarization-info"
    }

}

extension NotarizationStatusResponse {
    var isDone: Bool { info?.status == "success" }
}
