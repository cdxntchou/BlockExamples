
Block GeometryShader_ControlBlock_Identity
{
	// geometry shader that does nothing, really
	// it just passes through all triangles and all values on the triangle vertices, without modification

	global partial struct GeomVert
	{
	}

	Inputs
	{
		[Triangle] InputStream<GeomVert> inStream;
		[MaxVertexCount(3)] [Triangle] OutputStream<GeomVert> outStream;
	}

	Outputs
	{
	}

	Outputs Apply(Inputs inputs)
	{
		outputs.outStream.Write(inputs.inStream.Read(0));
		outputs.outStream.Write(inputs.inStream.Read(1));
		outputs.outStream.Write(inputs.inStream.Read(2));

		Outputs outputs;
		return outputs;
	}
}

