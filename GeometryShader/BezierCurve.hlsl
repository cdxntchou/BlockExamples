
Block GeometryShader_ControlBlock_BezierCurveFromLine
{
	// subdivides a line (with adjacency info) into multiple lines approximating a bezier curve
	// applies linear interpolation to all values, except position is interpolated via the bezier curve

	global partial struct GeomVert
	{
		inout float3 position;
	}

	Inputs
	{
		// number of output lines per input line
		[default(5)] int subdivisionCount;

		// input and output streams
		[LineAdjacency] InputStream<GeomVert> inStream;
		[MaxVertexCount(200)] [Line] OutputStream<GeomVert> outStream;
	}

	Outputs
	{
	}

	Outputs Apply(Inputs inputs)
	{
		GeomVert v[4];
		v[0] = inputs.inStream.Read(0);
		v[1] = inputs.inStream.Read(1);
		v[2] = inputs.inStream.Read(2);
		v[3] = inputs.inStream.Read(3);

		float dt = 1.0f / float(uNum);
		float t = 0.0f;

		for (int i = 0; i <= uNum; i++)
		{
			float omt = 1.0f - t;
			float omt2 = omt * omt;
			float omt3 = omt * omt2;
			float t2 = t * t;
			float t3 = t * t2;

			// linear interpolate everything
			GeomVert blended = Blend2<GeomVert>(
				v[1], omt,
				v[2], t);

			// spline interpolate position
			blended.position =
				v[0].position * omt3 +
				v[1].position * (3.0f * t * omt2) +
				v[2].position * (3.0f * t2 * omt) +
				v[3].position * t3);

			inputs.outStream.Write(blended);
			t += dt;
		}
	}
}

