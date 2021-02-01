//
// database abstraction
//
// goal is to allow different implementations of the database
//  first implementation is compatibile with workspace++, flat directory with YAML entries
//  second implementation is one directory per user with YAML entries, this lowers metadata load

import std.stdio;
import std.path;
import config;


// interface to access the database
interface Database {
	// return list of entries 
	string[] matchPattern(string pattern, string filesystem, string user, string[] groups, bool deleted, bool groupworkspaces);
	// TODO
	// read entry	
	// write entry
	// expire entry
	// ...	
}

class FilesystemDB : Database {
private:
	Config config;
public:
	this(Config config) {
		this.config = config;
	}

	// return list of identifiers of DB entries matching pattern from filesystem or all valid filesystems
	//  does not check if request for "deleted" is valid, has to be done on caller side
	string[] matchPattern(string pattern, string filesystem, string user, string[] groups, bool deleted, bool groupworkspaces) {
		string[] fslist ;
		string filepattern;

		if (filesystem!="") {
			if(config.hasAccess(user, groups, filesystem)) {
				fslist ~= filesystem;
			} else {
				// FIXME exception here instead of IO? will throw up ugly later anyhow
				stderr.writeln("error: invalid filesystem specified.");
			}
		} else {
			fslist ~= config.validFilesystems(user, groups);
		}

		string[] listdir(string pathname, string filepattern) {
		    import std.algorithm;
		    import std.array;
		    import std.file;
		    import std.path;

		    return std.file.dirEntries(pathname, filepattern, SpanMode.shallow)
			.filter!(a => a.isFile)
			.map!(a => baseName(a.name))
			.array;
		}	

		// this has to happen here, as other DB might have different patterns
		filepattern = user ~ "-" ~ pattern;

		if (deleted) 
			return listdir(buildPath(config.database(filesystem),config.deleted(filesystem)), filepattern);
		else 
			return listdir(config.database(filesystem), filepattern);
	}


}
