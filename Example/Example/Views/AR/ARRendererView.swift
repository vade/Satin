//
//  ARRendererView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

#if os(iOS)

import Forge
import SwiftUI

struct ARRendererView: View {
    var body: some View {
        ForgeView(renderer: ARRenderer())
            .ignoresSafeArea()
            .navigationTitle("AR Hello World")
    }
}

struct ARRendererView_Previews: PreviewProvider {
    static var previews: some View {
        ARRendererView()
    }
}

#endif
