//
//  ARBackgroundDepthRenderer.swift
//  Example
//
//  Created by Reza Ali on 4/11/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import Combine
import Foundation

import ARKit
import Metal
import MetalKit
import MetalPerformanceShaders

import Satin

class ARBackgroundDepthRenderer: ARBackgroundRenderer {
    class BackgroundDepthMaterial: SourceMaterial {
        public var upscaledDepthTexture: MTLTexture?
        public var depthTexture: CVMetalTexture?

        required init() {
            super.init(pipelinesURL: Bundle.main.resourceURL!
                .appendingPathComponent("Assets")
                .appendingPathComponent("Shared")
                .appendingPathComponent("Pipelines")
            )
            depthWriteEnabled = true
            blending = .alpha
        }

        required init(from _: Decoder) throws {
            fatalError("init(from:) has not been implemented")
        }

        override func bind(_ renderEncoder: MTLRenderCommandEncoder, shadow: Bool) {
            super.bind(renderEncoder, shadow: shadow)
            if let upscaledDepthTexture = upscaledDepthTexture {
                renderEncoder.setFragmentTexture(upscaledDepthTexture, index: FragmentTextureIndex.Custom0.rawValue)
            }
            else if let depthTexture = depthTexture {
                renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(depthTexture), index: FragmentTextureIndex.Custom0.rawValue)
            }
        }
    }

    unowned var sessionPublisher: ARSessionPublisher
    private var sessionSubscriptions = Set<AnyCancellable>()

    private lazy var background = Object("AR Background", [depthMesh, mesh])

    private var depthRenderer: Satin.Renderer
    private var depthAnchorPlaneMeshMap: [UUID: ARPlaneMesh] = [:]
    private var depthAnchorLidarMeshMap: [UUID: ARLidarMesh] = [:]

    private var depthScene = Object("Depth Scene")
    private var depthMesh: Mesh
    private var depthCamera: ARPerspectiveCamera

    private var depthUpscaler: ARDepthUpscaler

    private var depthMaterial = {
        let material = BasicColorMaterial([1, 1, 1, 0], .alpha)
        material.depthBias = DepthBias(bias: 5, slope: 5, clamp: 5)
        return material
    }()

    private var depthLidarMaterial = {
        let material = BasicColorMaterial([1, 1, 1, 0], .alpha)
        material.depthBias = DepthBias(bias: 5, slope: 5, clamp: 5)
        return material
    }()

    private var backgroundDepthMaterial: BackgroundDepthMaterial

    public private(set) var depthTexture: CVMetalTexture? {
        didSet {
            backgroundDepthMaterial.depthTexture = depthTexture
        }
    }

    public private(set) var upscaledDepthTexture: MTLTexture? {
        didSet {
            backgroundDepthMaterial.upscaledDepthTexture = upscaledDepthTexture
        }
    }

    public init(
        context: Context,
        session: ARSession,
        sessionPublisher: ARSessionPublisher,
        mtkView: MTKView,
        near: Float = 0.01,
        far: Float = 10.0
    ) {
        depthRenderer = Satin.Renderer(context: context)
        depthRenderer.label = "AR Background"

        depthRenderer.colorLoadAction = .clear
        depthRenderer.colorStoreAction = .store

        depthRenderer.depthLoadAction = .clear
        depthRenderer.depthStoreAction = .store

        depthCamera = ARPerspectiveCamera(session: session, mtkView: mtkView, near: near, far: far)

        self.sessionPublisher = sessionPublisher

        backgroundDepthMaterial = BackgroundDepthMaterial()
        backgroundDepthMaterial.set("Near Far Delta", [near, far, far - near])

        depthMesh = Mesh(geometry: Geometry(), material: backgroundDepthMaterial)
        depthMesh.label = "AR Depth Mesh"
        depthMesh.visible = false

        depthUpscaler = ARDepthUpscaler(device: context.device)

        super.init(context: context, session: session)

        mesh.label = "AR Color Mesh"
        mesh.material!.depthCompareFunction = .always

        depthCamera.add(background)
        depthScene.attach(background)

        setupSessionSubscriptions()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    func update(_ commandBuffer: MTLCommandBuffer) {
        super.update()

        if let capturedImageTextureY = capturedImageTextureY,
           let yTexture = CVMetalTextureGetTexture(capturedImageTextureY),
           let capturedImageTextureCbCr = capturedImageTextureCbCr,
           let cbcrTexture = CVMetalTextureGetTexture(capturedImageTextureCbCr),
           let depthTexture = depthTexture,
           let depthTexture = CVMetalTextureGetTexture(depthTexture)
        {
            upscaledDepthTexture = depthUpscaler.update(
                commandBuffer: commandBuffer,
                yTexture: yTexture,
                cbcrTexture: cbcrTexture,
                depthTexture: depthTexture
            )
        }

        background.scale = [depthCamera.aspect, 1.0, 1.0]
        background.position = [0, 0, -1.0 / tan(degToRad(depthCamera.fov * 0.5))]
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        update(commandBuffer)

        depthRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: depthScene,
            camera: depthCamera
        )
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, renderTarget: MTLTexture) {
        update(commandBuffer)

        depthRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: depthScene,
            camera: depthCamera,
            renderTarget: renderTarget
        )
    }

    override func resize(_ size: (width: Float, height: Float)) {
        super.resize(size)
        depthRenderer.resize(size)
    }

    // MARK: - Depth Updates

    override func updateTextures(_ frame: ARFrame) {
        super.updateTextures(frame)
        updateDepthTexture(frame)
    }

    internal func updateDepthTexture(_ frame: ARFrame) {
        if let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            let depthPixelBuffer = sceneDepth.depthMap
            if let depthTexturePixelFormat = getMTLPixelFormat(for: depthPixelBuffer) {
                depthTexture = createTexture(
                    fromPixelBuffer: depthPixelBuffer,
                    pixelFormat: depthTexturePixelFormat,
                    planeIndex: 0
                )

                depthMesh.visible = true
            }
        }
    }

    override func updateGeometry(_ frame: ARFrame) {
        super.updateGeometry(frame)
        depthMesh.geometry = mesh.geometry
    }

    internal func getMTLPixelFormat(for pixelBuffer: CVPixelBuffer) -> MTLPixelFormat? {
        if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat32 {
            return .r32Float
        }
        else if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 {
            return .r8Uint
        }
        else {
            return nil
        }
    }

    // MARK: - AR Session

    internal func setupSessionSubscriptions() {
        sessionPublisher.addedAnchorsPublisher.sink { [weak self] anchors in
            self?.addedAnchors(anchors)
        }.store(in: &sessionSubscriptions)

        sessionPublisher.updatedAnchorsPublisher.sink { [weak self] anchors in
            self?.updatedAnchors(anchors)
        }.store(in: &sessionSubscriptions)

        sessionPublisher.removedAnchorsPublisher.sink { [weak self] anchors in
            self?.removedAnchors(anchors)
        }.store(in: &sessionSubscriptions)
    }

    internal func addedAnchors(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let planeMesh = ARPlaneMesh(
                    label: anchor.identifier.uuidString,
                    anchor: planeAnchor,
                    material: depthMaterial
                )
                depthAnchorPlaneMeshMap[anchor.identifier] = planeMesh
                depthScene.add(planeMesh)
            }
            else if let meshAnchor = anchor as? ARMeshAnchor {
                let lidarMesh = ARLidarMesh(meshAnchor: meshAnchor, material: depthLidarMaterial)
                depthAnchorLidarMeshMap[anchor.identifier] = lidarMesh
                depthScene.add(lidarMesh)
            }
        }
    }

    internal func updatedAnchors(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                if let planeMesh = depthAnchorPlaneMeshMap[anchor.identifier] {
                    planeMesh.anchor = planeAnchor
                }
            }
            else if let meshAnchor = anchor as? ARMeshAnchor {
                if let lidarMesh = depthAnchorLidarMeshMap[anchor.identifier] {
                    lidarMesh.meshAnchor = meshAnchor
                }
            }
        }
    }

    internal func removedAnchors(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                if let mesh = depthAnchorPlaneMeshMap.removeValue(forKey: planeAnchor.identifier) {
                    depthScene.remove(mesh)
                }
            }
            else if let meshAnchor = anchor as? ARMeshAnchor {
                if let mesh = depthAnchorLidarMeshMap.removeValue(forKey: meshAnchor.identifier) {
                    depthScene.remove(mesh)
                }
            }
        }
    }
}

#endif
