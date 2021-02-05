

class ExitException : Exception {
	int status;
	this(int _status=0, string file=__FILE__, size_t
		line=__LINE__)
	{
		super("Program exit", file, line);
		status = _status;
	}
}
void exit(int status=0) {
	throw new ExitException(status);
}
