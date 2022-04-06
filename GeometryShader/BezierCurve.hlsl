
Block GeometryShader_ControlBlock_BezierCurveFromLine
{
	// subdivides a line (with adjacency info) into multiple lines approximating a bezier curve
	// applies linear interpolation to all values, except position is interpolated via the bezier curve

	// this is the structure representing a Geometry Shader Vertex (both input and output!)
	// it is declared global (because we want other blocks to share the same declaration)
	// and partial (because this is not a full description of the struct).
	// other blocks may declare their own members if they work with different information.
	global partial struct GeomVert
	{
		// the inout flags indicate that this block is explicitly reading positionWS from the structure,
		// and explicitly writing positionWS and positionCS.
		inout float3 positionWS;
		out float3 positionCS;
	}

	// inputs to the block
	Inputs
	{
		// number of output line segments for each input line segment
		[default(5)] int subdivisionCount;

		// input and output streams for the geometry shader
		// InputStream<GeomVert> is a generated type that can read from the input stream into a GeomVert struct
		// OutputStream<GeomVert> is a generated type that can write to the output stream from a GeomVert struct
		// [LineAdjacency] means the input is a line strip, with adjacency
		// (you get not just the end points of the current line, but also immediately preceding and following points)
		// [Line] means the output is a line strip
		[LineAdjacency] InputStream<GeomVert> inStream;
		[MaxVertexCount(200)] [Line] OutputStream<GeomVert> outStream;
	}

	Outputs
	{
	}

	// entry point for the block
	Outputs Apply(Inputs inputs)
	{
		// line with adjacency input provides four vertices.. read them
		GeomVert v[4];
		v[0] = inputs.inStream.Read(0);
		v[1] = inputs.inStream.Read(1);
		v[2] = inputs.inStream.Read(2);
		v[3] = inputs.inStream.Read(3);

		float dt = 1.0f / float(uNum);
		float t = 0.0f;

		// for each subdivision
		for (int i = 0; i <= uNum; i++)
		{
			float omt = 1.0f - t;
			float omt2 = omt * omt;
			float omt3 = omt * omt2;
			float t2 = t * t;
			float t3 = t * t2;

			// linear interpolate everything:  Blend2<GeomVert> will blend two GeomVert structures
			GeomVert blended = Blend2<GeomVert>(
				v[1], omt,
				v[2], t);

			// spline interpolate position:  replace position with the bezier spline interpolated value
			blended.positionWS =
				v[0].positionWS * omt3 +
				v[1].positionWS * (3.0f * t * omt2) +
				v[2].positionWS * (3.0f * t2 * omt) +
				v[3].positionWS * t3);

			// transform to clip space
			blended.positionCS = TransformPoint(blended.positionWS);

			// write the generated vertex out
			inputs.outStream.Write(blended);
			t += dt;
		}
	}
}

