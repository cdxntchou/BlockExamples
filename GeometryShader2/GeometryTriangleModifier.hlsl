//------------
//- Template -
//------------

Template Lit_WithGeometryTriangleModifier
{
	DeriveFromTemplate Lit   // i.e. the template with just vertex and fragment stages

	// define a geometry stage
	// in general, this geometry stage definition should work injected into just about any vertex/fragment pass
	// so ideally we have a way to insert this geometry stage into all passes from Lit
	GeometryStage
	{
		// the GeometryStage linker is looking for these input and output streams
		// to define the I/O of the geometry shader
		[Triangle]
		in Stream inStream;

		[MaxVertexCount(3)]
		[Triangle]
		out Stream outStream;

		CustomizationPoint setup
		{
		}

		// StreamInstances (name TBD) are a group of related values -- in this case, each StreamInstance
		// contains all values pertaining to a vertex in the input or output stream.

		// StreamInstances allow blocks to add values to them; they are not a fixed struct,
		// but rather a representation of a set of values that can be passed around as a group.

		CustomizationPoint preTriangleVertexOperations
		{
			// maybe would be nice to be able to declare a StreamInstance interface once somewhere,
			// as we use the same interface every place we want to pass one around here
			inout StreamInstance v
			{
				inout float3 positionWS;
				inout float3 normalWS;
				inout float3 tangentWS;
				inout float3 bitangentWS;
			}
		}

		CustomizationPoint triangleOperations
		{
			inout StreamInstance v0;
			{
				inout float3 positionWS;
				inout float3 normalWS;
				inout float3 tangentWS;
				inout float3 bitangentWS;
			}

			inout StreamInstance v1;
			{
				inout float3 positionWS;
				inout float3 normalWS;
				inout float3 tangentWS;
				inout float3 bitangentWS;
			}

			inout StreamInstance v2;
			{
				inout float3 positionWS;
				inout float3 normalWS;
				inout float3 tangentWS;
				inout float3 bitangentWS;
			}
		}

		CustomizationPoint postTriangleVertexOperations
		{
			inout StreamInstance v;
			{
				inout float3 positionWS;
				inout float3 normalWS;
				inout float3 tangentWS;
				inout float3 bitangentWS;
			}
		}

		BlockSequence Apply
		{
			setup();

			// copy assignments
			v0 = inStream[0];
			v1 = inStream[1];
			v2 = inStream[2];

			// apply per-vertex operations (before triangle operations)
			preTriangleVertexOperations(v0);		// positional param matching syntax (would be nice)
			preTriangleVertexOperations(v1);
			preTriangleVertexOperations(v2);

			// apply triangle operations
			triangleOperations;

			// apply per-vertex operations (after triangle operations)
			postTriangleVertexOperations(v: v0);	// named parameter matching
			postTriangleVertexOperations(v: v1);
			postTriangleVertexOperations(v: v2);

			// write to output stream (must be done in a block sequence)
			outStream.Emit(v0);
			outStream.Emit(v1);
			outStream.Emit(v2);
		}
	}
}



//---------------
//- User shader -
//---------------


// these example blocks could be included from a library of geo effects (once we have that)
Block SetTriangleToFlatShaded
{
	// override vertex normals to flat shade the triangle

	// use of a StreamInstance type means this block can not concretized until we resolve
	// the active StreamInstance members, as the concrete local type must be generated to match them
	inout StreamInstance v0, v1, v2
	{
		// in and out declarations help us populate the StreamInstance when linking
		in float3 positionWS;		// in makes a value live upstream (and issues an error if no value or default is provided)
		out float3 normalWS;		// out adds the value, or marks it as dead upstream if it is already there
	}

	void Apply()
	{
		float3 e0 = v1.positionWS - v0.positionWS;
		float3 e1 = v2.positionWS - v0.positionWS;
		float3 flatNormal = normalize(cross(e0, e1));  // might have this backwards.. depends on triangle cull winding

		v0.normalWS = flatNormal;
		v1.normalWS = flatNormal;
		v2.normalWS = flatNormal;
	}
}


Block ShrinkEraseTriangle
{
	// shrink the rasterized area of each triangle,
	// while keeping interior fragment results constant

	// inside HLSL-backed blocks, StreamInstances can be represented as a locally-defined struct type that has ALL of the visible data in the StreamInstance

	typedef StreamInstance LocalVertex
	{
		// in this case, this block doesn't actually need to know about ANY of the members of the type
		// as we only use generic struct operations
	};

	inout LocalVertex v0, v1, v2;

	[Property] [default(0.5f)]
	in float shrinkAmount;

	void Apply()
	{
		LocalVertex vCenter = Blend3<LocalVertex>(v0, 0.333f, v1, 0.333f, v2, 0.334f);
		v0 = Lerp<LocalVertex>(v0, vCenter, shrinkAmount);
		v1 = Lerp<LocalVertex>(v1, vCenter, shrinkAmount);
		v2 = Lerp<LocalVertex>(v2, vCenter, shrinkAmount);
	}
}


Block ExplodeMeshTriangle
{
	// split the mesh into separate triangles and make them fly apart like in an explosion
	// applying an initial velocity, gravity and a rotation to each triangle independently

	inout StreamInstance v0, v1, v2
	{
		inout float3 positionWS;
		inout float3 normalWS;
		inout float3 tangentWS;
		inout float3 bitangentWS;
	};

	[Property] [default(float3(0.0f,0.0f,0.0f))]
	in float3 explosionOrigin;
	[Property] [default(1.0f)]
	in float initialVelocityMultiplier;
	[Property] [default(1.0f)]
	in float rotationSpeed;
	[Property] [default(1.0f)]
	in float gravityAcceleration;

	[default(0.0f)]
	in float time;		// time since the explosion occurred (must be hooked up)

	void Apply()
	{
		float3 vCenterPosWS = v0.positionWS * 0.333f + v1.positionWS * 0.333f + v2.positionWS * 0.334f;
		float3 initialVelocity = (vCenterPosWS - explosionOrigin) * initialVelocityMultipler;
		float3 rotationAxis = normalize(cross(initialVelocity, float3(0.0f, 1.0f, 0.0f)));

		// calculate new center position applying velocity and gravity
		float3 newCenterPositionWS = vCenterPosWS + initialVelocity * time + float3(0.0f, -gravityAcceleration, 0.0f) * time * time;
		float3x3 rotationMatrix = MatrixFromAxisAngle(rotationAxis, time * rotationSpeed);

		// rotate points around vCenter by rotation matrix, then offset to new position
		v0.positionWS = rotationMatrix * (v0.positionWS - vCenter.positionWS) + newCenterPositionWS;
		v0.normalWS = rotationMatrix * v0.normalWS;
		v0.tangentWS = rotationMatrix * v0.tangentWS;
		v0.bitangentWS = rotationMatrix * v0.bitangentWS;

		v1.positionWS = rotationMatrix * (v1.positionWS - vCenter.positionWS) + newCenterPositionWS;
		v1.normalWS = rotationMatrix * v1.normalWS;
		v1.tangentWS = rotationMatrix * v1.tangentWS;
		v1.bitangentWS = rotationMatrix * v1.bitangentWS;

		v2.positionWS = rotationMatrix * (v2.positionWS - vCenter.positionWS) + newCenterPositionWS;
		v2.normalWS = rotationMatrix * v2.normalWS;
		v2.tangentWS = rotationMatrix * v2.tangentWS;
		v2.bitangentWS = rotationMatrix * v2.bitangentWS;
	}
}


Block OffsetPositionAlongNormal
{
	typedef StreamInstance LocalVertex
	{
		inout float3 positionWS;
		in float3 normalWS;
	};

	inout LocalVertex v;

	[Property]
	[default(1.0f)]
	in float offsetAmount;

	Outputs Apply(Inputs inputs)
	{
		v.positionWS += v.normalWS * offsetAmount;
	}
}



Shader ExplodeMyMeshShader
{
	DeclareSubShaderUsingTemplate(Lit_WithGeometryTriangleModifier)
	{
		// fill out Geometry Customization Points
		setup = BlockGraph
		{
			Block SetupExplosionTimer
			{
				[UnitySystemValue("_Time")]		// however we get _Time system value
				in float4 time;

				[Property]						// make this a property, going to set it from script
				in float explodeStartTime;

				out float explodeTime;

				void Apply()
				{
					explodeTime = max(time.y - explodeStartTime, 0.0f);
				}
			};
		};

		triangleOperations = BlockGraph
		{
			ExplodeMeshTriangle(time: explodeTime);
			Block CalculateShrinkAmount // wouldn't need this block if we could inline simple expressions for in parameters... :)
			{
				in float explodeTime;
				out float shrinkAmount;
				void Apply()
				{
					shrinkAmount = 1.0f / max(explodeTime, 1.0f);
				}
			};
			ShrinkEraseTriangle(shrinkAmount : shrinkAmount);
			SetTriangleToFlatShaded();
		};

		postTriangleVertexOperations = BlockGraph
		{
			Block AnimateVertexColor
			{
				// animate vertex color from white to a world space rainbow over 2 seconds
				// (stomps any existing vertex color)

				in float explodeTime;

				// might be able to define it slightly differently to allow selective reading of inputs
				// and don't require copying ALL the data every time a StreamInstance is passed
				inout StreamInstance v
				{
					in float3 positionWS;
					out float4 vertexColor;
				}

				void Apply()
				{
					vertexColor = lerp(float4(1, 1, 1, 1), float4(frac(positionWS.xyz), 1), saturate(explodeTime * 0.5f));
				}
			};
		};
	}
}



//-------------------------
// Linker generated code: -
//-------------------------

Shader ExplodeMyMeshShader
{
	Properties
	{
		// not bothering to translate to ShaderLab syntax, but you get the idea
		float explodeStartTime;		
		float3 explosionOrigin			[default(float3(0.0f, 0.0f, 0.0f))];
		float initialVelocityMultiplier	[default(1.0f)];
		float rotationSpeed				[default(1.0f)];
		float gravityAcceleration		[default(1.0f)];
	}

	SubShader 
	{
		Pass
		{
			// declare uniforms
			float explodeStartTime;
			float3 explosionOrigin;
			float initialVelocityMultiplier;
			float rotationSpeed;
			float gravityAcceleration;

			// block definitions
			struct SetupExplosionTimer
			{
				float4 time;
				float explodeStartTime;
				float explodeTime;
				void Apply()
				{
					explodeTime = max(time.y - explodeStartTime, 0.0f);
				}
			}

			struct ExplodeMeshTriangle
			{
				// generated struct (but can be generated locally - no link context involved)
				struct StreamInstanceStruct
				{
					float3 positionWS;
					float3 normalWS;
					float3 tangentWS;
					float3 bitangentWS;
				};

				StreamInstanceStruct v0, v1, v2;
				float3 explosionOrigin;
				float initialVelocityMultiplier;
				float rotationSpeed;
				float gravityAcceleration;
				float time;

				void Apply()
				{
					float3 vCenterPosWS = v0.positionWS * 0.333f + v1.positionWS * 0.333f + v2.positionWS * 0.334f;
					float3 initialVelocity = (vCenterPosWS - explosionOrigin) * initialVelocityMultipler;
					float3 rotationAxis = normalize(cross(initialVelocity, float3(0.0f, 1.0f, 0.0f)));

					// calculate new center position applying velocity and gravity
					float3 newCenterPositionWS = vCenterPosWS + initialVelocity * time + float3(0.0f, -gravityAcceleration, 0.0f) * time * time;
					float3x3 rotationMatrix = MatrixFromAxisAngle(rotationAxis, time * rotationSpeed);

					// rotate points around vCenter by rotation matrix, then offset to new position
					v0.positionWS = rotationMatrix * (v0.positionWS - vCenter.positionWS) + newCenterPositionWS;
					v0.normalWS = rotationMatrix * v0.normalWS;
					v0.tangentWS = rotationMatrix * v0.tangentWS;
					v0.bitangentWS = rotationMatrix * v0.bitangentWS;

					v1.positionWS = rotationMatrix * (v1.positionWS - vCenter.positionWS) + newCenterPositionWS;
					v1.normalWS = rotationMatrix * v1.normalWS;
					v1.tangentWS = rotationMatrix * v1.tangentWS;
					v1.bitangentWS = rotationMatrix * v1.bitangentWS;

					v2.positionWS = rotationMatrix * (v2.positionWS - vCenter.positionWS) + newCenterPositionWS;
					v2.normalWS = rotationMatrix * v2.normalWS;
					v2.tangentWS = rotationMatrix * v2.tangentWS;
					v2.bitangentWS = rotationMatrix * v2.bitangentWS;
				}
			};

			struct CalculateShrinkAmount
			{
				in float explodeTime;
				out float shrinkAmount;
				void Apply()
				{
					shrinkAmount = 1.0f / max(explodeTime, 1.0f);
				}
			};

			struct ShrinkEraseTriangle(shrinkAmount : shrinkAmount)
			{
				// generated struct that wishes to access all visible members of the group
				// this generation must be deferred to link time to know the visible members
				struct LocalVertex
				{
					// obfuscated names (append with block hash), as nothing was declared for direct access
					float3 positionWS_103ABE342;
					float3 normalWS_103ABE342;
					float3 tangentWS_103ABE342;
					float3 bitangentWS_103ABE342;
					float4 vertexColor_103ABE342;
				};

				LocalVertex v0, v1, v2;
				float shrinkAmount;

				// generated functions
				LocalVertex Blend3_LocalVertex(LocalVertex v0, float w0, LocalVertex v1, float v1, LocalVertex v2, float v2)
				{
					// ... you can imagine what goes here
				}
				LocalVertex Lerp_LocalVertex(LocalVertex a, LocalVertex b, float t)
				{
					// ... you can imagine what goes here
				}

				void Apply()
				{
					LocalVertex vCenter = Blend3_LocalVertex(v0, 0.333f, v1, 0.333f, v2, 0.334f);
					v0 = Lerp_LocalVertex(v0, vCenter, shrinkAmount);
					v1 = Lerp_LocalVertex(v1, vCenter, shrinkAmount);
					v2 = Lerp_LocalVertex(v2, vCenter, shrinkAmount);
				}
			};

			struct SetTriangleToFlatShaded
			{
				struct StreamInstanceStruct
				{
					float3 positionWS;
					float3 normalWS;
				};
				StreamInstanceStruct v0, v1, v2;
			};

			struct AnimateVertexColor
			{
				float explodeTime;
				float3 positionWS;
				float4 vertexColor;
				void Apply()
				{
					vertexColor = lerp(float4(1, 1, 1, 1), float4(frac(positionWS.xyz), 1), saturate(explodeTime * 0.5f));
				}
			};

			// entry points
			[maxvertexcount(3)]
			void GeometryStageEntryPoint(triangle V2G inStream[3], inout TriangleStream<G2F> outStream)
			{
				// setup customization point invocation
				float explodeTime;
				{
					SetupExplosionTimer block = 0;
					block.time = _Time;
					block.explodeStartTime = explodeStartTime;
					block.Apply()
					explodeTime = block.explodeTime;
				}

				// copy assignments
				V2G v0 = inStream[0];
				V2G v1 = inStream[1];
				V2G v2 = inStream[2];

				// apply per-vertex operations (before triangle operations)
				{
					// no-op no blocks
				}
				{
					// no-op no blocks
				}
				{
					// no-op no blocks
				}

				// apply triangle operations
				{
					ExplodeMeshTriangle block = 0;
					block.v0.positionWS = v0.positionWS;
					block.v0.normalWS = v0.normalWS;
					block.v0.tangentWS = v0.tangentWS;
					block.v0.bitangentWS = v0.bitangentWS;
					block.v1.positionWS = v1.positionWS;
					block.v1.normalWS = v1.normalWS;
					block.v1.tangentWS = v1.tangentWS;
					block.v1.bitangentWS = v1.bitangentWS;
					block.v2.positionWS = v2.positionWS;
					block.v2.normalWS = v2.normalWS;
					block.v2.tangentWS = v2.tangentWS;
					block.v2.bitangentWS = v2.bitangentWS;
					block.Apply();
					v0.positionWS = block.v0.positionWS;
					v0.normalWS = block.v0.normalWS;
					v0.tangentWS = block.v0.tangentWS;
					v0.bitangentWS = block.v0.bitangentWS;
					v1.positionWS = block.v1.positionWS;
					v1.normalWS = block.v1.normalWS;
					v1.tangentWS = block.v1.tangentWS;
					v1.bitangentWS = block.v1.bitangentWS;
					v2.positionWS = block.v2.positionWS;
					v2.normalWS = block.v2.normalWS;
					v2.tangentWS = block.v2.tangentWS;
					v2.bitangentWS = block.v2.bitangentWS;
				}
				float shrinkAmount;
				{
					CalculateShrinkAmount block = 0;
					block.explodeTime = explodeTime;
					block.Apply();
					shrinkAmount = block.shrinkAmount;
				}

				{
					ShrinkEraseTriangle block = 0;
					block.v0.positionWS_103ABE342 = v0.positionWS;
					block.v0.normalWS_103ABE342 = v0.normalWS;
					block.v0.tangentWS_103ABE342 = v0.tangentWS;
					block.v0.bitangentWS_103ABE342 = v0.bitangentWS;
					block.v0.vertexColor_103ABE342 = v0.vertexColor;
					block.v1.positionWS_103ABE342 = v1.positionWS;
					block.v1.normalWS_103ABE342 = v1.normalWS;
					block.v1.tangentWS_103ABE342 = v1.tangentWS;
					block.v1.bitangentWS_103ABE342 = v1.bitangentWS;
					block.v1.vertexColor_103ABE342 = v1.vertexColor;
					block.v2.positionWS_103ABE342 = v2.positionWS;
					block.v2.normalWS_103ABE342 = v2.normalWS;
					block.v2.tangentWS_103ABE342 = v2.tangentWS;
					block.v2.bitangentWS_103ABE342 = v2.bitangentWS;
					block.v2.vertexColor_103ABE342 = v2.vertexColor;
					block.Apply();
					v0.positionWS = v0.positionWS_103ABE342;
					v0.normalWS = v0.normalWS_103ABE342;
					v0.tangentWS = v0.tangentWS_103ABE342;
					v0.bitangentWS = v0.bitangentWS_103ABE342;
					v0.vertexColor = v0.vertexColor_103ABE342;
					v1.positionWS = v1.positionWS_103ABE342;
					v1.normalWS = v1.normalWS_103ABE342;
					v1.tangentWS = v1.tangentWS_103ABE342;
					v1.bitangentWS = v1.bitangentWS_103ABE342;
					v1.vertexColor = v1.vertexColor_103ABE342;
					v2.positionWS = v2.positionWS_103ABE342;
					v2.normalWS = v2.normalWS_103ABE342;
					v2.tangentWS = v2.tangentWS_103ABE342;
					v2.bitangentWS = v2.bitangentWS_103ABE342;
					v2.vertexColor = v2.vertexColor_103ABE342;
				}
				{
					SetTriangleToFlatShaded block = 0;
					block.v0.positionWS = v0.positionWS;
					block.v1.positionWS = v1.positionWS;
					block.v2.positionWS = v2.positionWS;
					block.Apply();
					v0.normalWS = block.v0.normalWS;
					v1.normalWS = block.v1.normalWS;
					v2.normalWS = block.v2.normalWS;
				}

				// apply per-vertex operations (after triangle operations)
				float4 vertexColor_v0;		// since vertex color is a new value in the group (not overriding an existing one), linker must create a variable to hold it
				{
					AnimateVertexColor block;
					block.explodeTime = explodeTime;
					block.positionWS = v0.positionWS;
					block.Apply();
					vertexColor_v0 = block.vertexColor;
				}
				float4 vertexColor_v1;
				{
					AnimateVertexColor block;
					block.explodeTime = explodeTime;
					block.positionWS = v1.positionWS;
					block.Apply();
					vertexColor_v1 = block.vertexColor;
				}
				float4 vertexColor_v2;
				{
					AnimateVertexColor block;
					block.explodeTime = explodeTime;
					block.positionWS = v2.positionWS;
					block.Apply();
					vertexColor_v2 = block.vertexColor;
				}

				// write to output stream (must be done in a block sequence)
				{
					// linker knows the HLSL representations of all values in the group and can generate output code if they are needed downstream
					G2F outData;
					outData.positionCS = v0.positionCS;
					outData.positionWS = v0.positionWS;
					outData.normalWS = v0.normalWS;
					outData.tangentWS = v0.tangentWS;
					outData.binormalWS = v0.binormalWS;
					outData.vertexColor = vertexColor_v0;
					outStream.Append(outData);
				}
				{
					G2F outData;
					outData.positionCS = v1.positionCS;
					outData.positionWS = v1.positionWS;
					outData.normalWS = v1.normalWS;
					outData.tangentWS = v1.tangentWS;
					outData.binormalWS = v1.binormalWS;
					outData.vertexColor = vertexColor_v1;
					outStream.Append(outData);
				}
				{
					G2F outData;
					outData.positionCS = v2.positionCS;
					outData.positionWS = v2.positionWS;
					outData.normalWS = v2.normalWS;
					outData.tangentWS = v2.tangentWS;
					outData.binormalWS = v2.binormalWS;
					outData.vertexColor = vertexColor_v2;
					outStream.Append(outData);
				}
			}
		}
	}
}
