//
//  FlipTimerWidgetBundle.swift
//  FlipTimerWidget
//
//  Created by Dave Latham on 1/7/26.
//

import WidgetKit
import SwiftUI

@main
struct FlipTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            FlipTimerWidgetLiveActivity()
        }
    }
}
