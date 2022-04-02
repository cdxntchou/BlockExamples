
Block GeometryShader_ControlBlock_VisualizeNormals
{
	// draws lines from each triangle vertex, visualizing the normal direction

	global partial struct GeomVert
	{
		in float3 normal;
		inout float3 position;
	}

	Inputs
	{
		// length of the normal
		[default(1.0f)] float length;

		// input and output streams
		[LineAdjacency] InputStream<GeomVert> inStream;
		[MaxVertexCount(200)] [Line] OutputStream<GeomVert> outStream;
	}

	Outputs
	{
	}

	void DrawNormal(GeomVert v, float length, OutStream<GeomVert> outStream)
	{
		outStream.Write(v);
		v.position += v.normal * length;
		outStream.Write(v);
		outStream.RestartStrip();
	}

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

