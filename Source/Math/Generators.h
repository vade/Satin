//
//  Generators.h
//  Satin
//
//  Created by Reza Ali on 6/5/20.
//

#ifndef Generators_h
#define Generators_h

#include <stdio.h>
#include "Types.h"

GeometryData generateIcoSphereGeometryData(float radius, int res);

GeometryData generateSquircleGeometryData(float size, float p, int angularResolution, int radialResolution);

#endif /* Generators_h */
