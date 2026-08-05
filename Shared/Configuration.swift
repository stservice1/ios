//
//  Configuration.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import CoreData
import Foundation

@objc(Configuration)
public final class Configuration: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var type: String
    @NSManaged public var content: String
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var sourceURL: String?
}

extension Configuration {
    var coreType: CoreType {
        get { CoreType(rawValue: type) ?? .xray }
        set { type = newValue.rawValue }
    }

    /// Swift-side analog of Android's `Profile.imported`: there's no
    /// separate "imported" flag in this Core Data model, but `content` is
    /// only ever non-empty once a subscription fetch has actually
    /// succeeded (ProfileFactory creates the row with empty content first,
    /// then fills it in), so emptiness doubles as that flag.
    var imported: Bool { !content.isEmpty }
}
