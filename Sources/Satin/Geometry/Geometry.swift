//
//  Geometry.swift
//  Satin
//
//  Created by Reza Ali on 7/23/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Metal
import simd

public protocol GeometryDelegate: AnyObject {
    func updated(geometry: Geometry)
}

open class Geometry {
    public var primitiveType: MTLPrimitiveType = .triangle
    public var windingOrder: MTLWinding = .counterClockwise
    public var indexType: MTLIndexType = .uint32
    public weak var delegate: GeometryDelegate?
    
    public var vertexData: [Vertex] = [] {
        didSet {
            delegate?.updated(geometry: self)
            setupVertexBuffer()
            _updateBounds = true
        }
    }
    
    public var indexData: [UInt32] = [] {
        didSet {
            delegate?.updated(geometry: self)
            setupIndexBuffer()
        }
    }
    
    public var context: Context? {
        didSet {
            setup()
        }
    }
    
    var _updateBounds: Bool = true
    var _bounds = Bounds(min: simd_float3(repeating: 0.0), max: simd_float3(repeating: 0.0))
    
    public var bounds: Bounds {
        if _updateBounds {
            _bounds = computeBounds()
            _updateBounds = false
        }
        return _bounds
    }
    
    public var vertexBuffer: MTLBuffer?
    public var indexBuffer: MTLBuffer?
    
    public init() {}
    
    public init(_ geometryData: inout GeometryData) {
        setFrom(&geometryData)
    }
    
    public init(primitiveType: MTLPrimitiveType, windingOrder: MTLWinding, indexType: MTLIndexType) {
        self.primitiveType = primitiveType
        self.windingOrder = windingOrder
        self.indexType = indexType
    }
    
    func setup() {
        setupVertexBuffer()
        setupIndexBuffer()
    }
    
    public func update() {}
    
    func setupVertexBuffer() {
        guard let context = context else { return }
        let device = context.device
        if !vertexData.isEmpty {
            let stride = MemoryLayout<Vertex>.stride
            let verticesSize = vertexData.count * stride
            vertexBuffer = device.makeBuffer(bytes: vertexData, length: verticesSize, options: [])
            vertexBuffer?.label = "Vertices"
        }
        else {
            vertexBuffer = nil
        }
    }
    
    func setupIndexBuffer() {
        guard let context = context else { return }
        let device = context.device
        if !indexData.isEmpty {
            let indicesSize = indexData.count * MemoryLayout.size(ofValue: indexData[0])
            indexBuffer = device.makeBuffer(bytes: indexData, length: indicesSize, options: [])
            indexBuffer?.label = "Indices"
        }
        else {
            indexBuffer = nil
        }
    }
    
    public func setFrom(_ geometryData: inout GeometryData) {
        let vertexCount = Int(geometryData.vertexCount)
        if vertexCount > 0, let data = geometryData.vertexData {
            vertexData = Array(UnsafeBufferPointer(start: data, count: vertexCount))
        }
        
        let indexCount = Int(geometryData.indexCount) * 3
        if indexCount > 0, let data = geometryData.indexData {
            data.withMemoryRebound(to: UInt32.self, capacity: indexCount) { ptr in
                indexData = Array(UnsafeBufferPointer(start: ptr, count: indexCount))
            }
        }
    }
    
    public func getGeometryData() -> GeometryData {
        var data = GeometryData()
        data.vertexCount = Int32(vertexData.count)
        data.indexCount = Int32(indexData.count / 3)
        
        vertexData.withUnsafeMutableBufferPointer { vtxPtr in
            data.vertexData = vtxPtr.baseAddress!
        }
        
        indexData.withUnsafeMutableBufferPointer { indPtr in
            let raw = UnsafeRawBufferPointer(indPtr)
            let ptr = raw.bindMemory(to: TriangleIndices.self)
            data.indexData = UnsafeMutablePointer(mutating: ptr.baseAddress!)
        }
        
        return data
    }
    
    public func unroll() {
        var data = getGeometryData()
        var unrolled = GeometryData()
        unrollGeometryData(&unrolled, &data)
        setFrom(&unrolled)
        freeGeometryData(&unrolled)
    }
    
    func computeBounds() -> Bounds {
        let count = vertexData.count
        var result = Bounds()
        vertexData.withUnsafeMutableBufferPointer { vtxPtr in
            result = computeBoundsFromVertices(vtxPtr.baseAddress!, Int32(count))
        }
        return result
    }
    
    deinit {
        indexData = []
        vertexData = []
        vertexBuffer = nil
        indexBuffer = nil
    }
}
