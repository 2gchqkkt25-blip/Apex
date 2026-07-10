//
//  EPGStaleScheduleAlign.swift
//  Apex
//
//  Intentionally empty — shifting uniformly stale schedules onto "now" was
//  removed. It made titles appear at the current time while the programme had
//  already changed days ago (movie channels). Live browse uses `limit=4`
//  `get_short_epg` + `now_playing` instead.
//

import Foundation
