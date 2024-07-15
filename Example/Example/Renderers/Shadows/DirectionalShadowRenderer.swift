//
//  ShadowRenderer.swift
//
//
//  Created by Reza Ali on 3/2/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Forge
import Satin

class DirectionalShadowRenderer: BaseRenderer {
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    let lightHelperGeo = BoxGeometry(size: (0.1, 0.1, 0.5))
    let lightHelperMat = BasicDiffuseMaterial(0.7)

    lazy var lightHelperMesh0 = Mesh(geometry: lightHelperGeo, material: lightHelperMat)
    lazy var lightHelperMesh1 = Mesh(geometry: lightHelperGeo, material: lightHelperMat)

    var baseMesh = Mesh(
        geometry: BoxGeometry(size: (1.25, 0.125, 1.25), res: 5),
        material: StandardMaterial(baseColor: [1.0, 1.0, 1.0, 1.0], metallic: 0.75, roughness: 0.25)
    )

    var torusMesh = Mesh(
        geometry: TorusGeometry(radius: (0.1, 0.5)),
        material: StandardMaterial(baseColor: [1, 1, 1, 1], metallic: 1.0, roughness: 0.25, specular: 1.0)
    )

    var sphereMesh = Mesh(
        geometry: IcoSphereGeometry(radius: 0.25, res: 3),
        material: StandardMaterial(baseColor: .one, metallic: 0.8, roughness: 0.5, specular: 1.0)
    )

    var floorMesh = Mesh(geometry: PlaneGeometry(size: 8.0, plane: .zx), material: ShadowMaterial())

    var light0 = DirectionalLight(color: [1.0, 1.0, 1.0], intensity: 1.0)
    var light1 = DirectionalLight(color: [1.0, 1.0, 1.0], intensity: 1.0)

    lazy var scene = Scene("Scene", [light0, light1, floorMesh, baseMesh, sphereMesh, torusMesh])
    lazy var context = Context(device, sampleCount, colorPixelFormat, depthPixelFormat, stencilPixelFormat)
    lazy var camera = PerspectiveCamera(position: .init(repeating: 5.0), near: 0.01, far: 500.0, fov: 30)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: mtkView)
    lazy var renderer = Satin.Renderer(context: context)

    override func setupMtkView(_ metalKitView: MTKView) {
        metalKitView.sampleCount = 1
        metalKitView.depthStencilPixelFormat = .depth32Float
//        metalKitView.preferredFramesPerSecond = 60
    }

    override init() {
        super.init()
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: MTLCreateSystemDefaultDevice()!, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr)
        }
    }

    override func setup() {
        renderer.clearColor = .init(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)

        light0.position.y = 5.0
        light0.castShadow = true
        lightHelperMesh0.label = "Light Helper 0"
        light0.add(lightHelperMesh0)
        if let shadowCamera = light0.shadow.camera as? OrthographicCamera {
            shadowCamera.update(left: -2, right: 2, bottom: -2, top: 2)
        }
        light0.shadow.resolution = (2048, 2048)
        light0.shadow.bias = 0.0005
        light0.shadow.strength = 0.25
        light0.shadow.radius = 2

        light1.position.y = 5.0
        light1.castShadow = true
        lightHelperMesh1.label = "Light Helper 1"
        light1.add(lightHelperMesh1)
        if let shadowCamera = light1.shadow.camera as? OrthographicCamera {
            shadowCamera.update(left: -2, right: 2, bottom: -2, top: 2)
        }
        light1.shadow.resolution = (2048, 2048)
        light1.shadow.bias = 0.0005
        light1.shadow.strength = 0.25
        light1.shadow.radius = 2

        // Setup things here
        camera.lookAt(target: .zero)
        floorMesh.position.y = -1.0

        torusMesh.label = "Main"
        torusMesh.castShadow = true
        torusMesh.receiveShadow = true

        sphereMesh.label = "Sphere"
        sphereMesh.castShadow = true
        sphereMesh.receiveShadow = true

        baseMesh.label = "Base"
        baseMesh.position.y = -0.75
        baseMesh.castShadow = true
        baseMesh.receiveShadow = true

        floorMesh.label = "Floor"
        floorMesh.material?.set("Color", [0.0, 0.0, 0.0, 1.0])
        floorMesh.receiveShadow = true
    }

    deinit {
        cameraController.disable()
    }

    lazy var startTime = getTime()

    override func update() {
        cameraController.update()

        let time = getTime() - startTime
        var theta = Float(time)
        let radius: Float = 5.0

        torusMesh.orientation = simd_quatf(angle: theta, axis: Satin.worldUpDirection)
        torusMesh.orientation *= simd_quatf(angle: theta, axis: Satin.worldRightDirection)

        light0.position = simd_make_float3(radius * sin(theta), 5.0, radius * cos(theta))
        light0.lookAt(target: .zero, up: Satin.worldUpDirection)

        theta += .pi * 0.5
        light1.position = simd_make_float3(radius * sin(theta), 5.0, radius * cos(theta))
        light1.lookAt(target: .zero, up: Satin.worldUpDirection)
    }

    override func draw(_ view: MTKView, _ commandBuffer: MTLCommandBuffer) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(_ size: (width: Float, height: Float)) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}
