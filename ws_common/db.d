//
// database abstraction
//
// goal is to allow different implementations of the database
//  first implementation is compatibile with workspace++, flat directory with YAML entries
//  second implementation is one directory per user with YAML entries, this lowers metadata load

import std.stdio;
import std.path;
import std.algorithm;
import std.array;
import std.string;
import config;
import dyaml;
import yamlhelper;


// interface to access the database
interface Database {
	// return list of entries 
	string[] matchPattern(string pattern, string filesystem, string user, string[] groups, bool deleted, bool groupworkspaces);
	// TODO
	// read entry	
	DBEntry readEntry(string filesystem, string user, string id, bool deleted);
	// write entry
	// expire entry
	// ...	
}


// dbentry
//  struct or assoc array?
//  if struct we might need a version field
//  assoc would be very flexible and match the YAML model well, easy to extend
//  and would carry unknown fields simply over. mix may be?
class DBEntry {
	int	dbversion;		// version
	long 	expiration;		// epoch time of expiration
	string 	workspace;		// directory path
	int 	extensions;		// extensions, counting down
	long	reminder;		// epoch time of reminder to be sent out
	string	mailaddress;		// address for reminder email
	string 	comment;		// some user defined comment

	// read db entry from yaml file
	void readFromfile(string filename) {
		auto root = Loader.fromFile(filename).load();
		dbversion = readValue!int(root, "dbversion", 0); 	// 0 = legacy
		expiration = readValue!long(root, "expiration", 0); 	
		workspace = readValue!string(root, "workspace", ""); 	
		extensions = readValue!int(root, "extensions", 0); 	
		reminder = readValue!long(root, "reminder", 0); 	
		mailaddress = readValue!string(root, "mailaddress", ""); 	
		comment = readValue!string(root, "comment", ""); 	
	}
}


// implementations of legacy DB format from workspace++
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
			return listdir(buildPath(config.database(filesystem),config.deleted(filesystem)), filepattern).
				map!(s => s[s.indexOf('-')+1..$]).array;
		else 
			return listdir(config.database(filesystem), filepattern).
				map!(s => s[s.indexOf('-')+1..$]).array;
	}

	// read DBentry and return it
	DBEntry readEntry(string filesystem, string user, string id, bool deleted) {
		auto entry = new DBEntry;
		string filename;
		if (deleted) 
			filename = buildPath(config.database(filesystem), config.deleted(filesystem), user~"-"~id);
		else 
			filename = buildPath(config.database(filesystem), user~"-"~id);
		entry.readFromfile(filename);
		return entry;
	}
}
