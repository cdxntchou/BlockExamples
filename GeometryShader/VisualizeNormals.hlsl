
Block GeometryShader_ControlBlock_VisualizeNormals
{
	// draws lines from each triangle vertex, visualizing the normal direction

	global partial struct GeomVert
	{
		in float3 normalWS;
		inout float3 positionWS;
		out float4 positionCS;
	}

	Inputs
	{
		// length of the normal
		[default(1.0f)] float length;

		// input triangle stream, output line stream
		[Triangle] InputStream<GeomVert> inStream;
		[MaxVertexCount(6)] [Line] OutputStream<GeomVert> outStream;
	}

	Outputs
	{
	}

	void DrawNormal(GeomVert v, float length, OutStream<GeomVert> outStream)
	{
		outStream.Write(v);
		v.positionWS += v.normalWS * length;
		v.positionCS = TransformPoint(v.positionWS);
		outStream.Write(v);
		outStream.RestartStrip();
	}

	// block entry point
	Outputs Apply(Inputs inputs)
	{
		GeomVert v;
		DrawNormal(inputs.inStream.Read(0), length, outStream);
		DrawNormal(inputs.inStream.Read(1), length, outStream);
		DrawNormal(inputs.inStream.Read(2), length, outStream);

		Outputs output;
		return output;
	}
}

