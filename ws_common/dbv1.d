import std.stdio;
import std.path;
import std.algorithm;
import std.array;
import std.string;
import std.conv;
import config;
import dyaml;
import yamlhelper;
import core.stdc.time;
import db;

// dbentry
//  struct or assoc array?
//  if struct we might need a version field
//  assoc would be very flexible and match the YAML model well, easy to extend
//  and would carry unknown fields simply over. mix may be?
class DBEntryV1 : DBEntry {
	int	dbversion;		// version
	string	id;			// ID of this workspace
	string	filesystem;		// location
	string 	workspace;		// directory path
	long	creation;		// epoch time of creation
	long 	expiration;		// epoch time of expiration
	long 	released;		// epoch time of manual release
	long	reminder;		// epoch time of reminder to be sent out
	int 	extensions;		// extensions, counting down
	string	group;			// group for whom it is visible
	string	mailaddress;		// address for reminder email
	string 	comment;		// some user defined comment

	// read db entry from yaml file
	bool readFromfile(string id, string filesystem, string filename) {
		Node root;
		try {
			root = Loader.fromFile(filename).load();
		} catch (dyaml.exception.YAMLException e) {
			stderr.writefln("error: yaml parser in file <%s>: %s", filename, e.msg);
			return false;
		}

		dbversion = readValue!int(root, "dbversion", 0); 	// 0 = legacy
		this.id = id;
		this.filesystem = filesystem;
		creation = readValue!long(root, "creation", 0); 	
		released = readValue!long(root, "released", 0); 	
		expiration = readValue!long(root, "expiration", 0); 	
		reminder = readValue!long(root, "reminder", 0); 	
		workspace = readValue!string(root, "workspace", ""); 	
		extensions = readValue!int(root, "extensions", 0); 	
		mailaddress = readValue!string(root, "mailaddress", ""); 	
		comment = readValue!string(root, "comment", ""); 	
		group = readValue!string(root, "group", ""); 	
		return true;
	}

	long getRemaining() {
		long remaining = expiration - time(cast(long *)0L);
		return remaining;
	}
	long getCreation() {
		return creation;
	}
	string getId() {
		return id;
	}
	string getGroup() {
		return group;
	}

	void print(bool verbose, bool terse) {
		string repr;
		long remaining = expiration - time(cast(long *)0L);

		stdout.writefln(
			"Id: %s\n" ~   
			"    workspace directory  : %s", 
			id, workspace);	
		if (remaining<0) {
			stdout.writefln("    remaining time       : %s", "expired");
		} else {
			stdout.writefln("    remaining time       : %d days, %d hours", remaining/(24*3600), (remaining%(24*3600))/3600);
		}
		if(!terse) {
			if(comment!="")
				stdout.writefln("    comment              : %s", comment);
			if (creation>0) 
				stdout.writef("    creation time        : %s", ctime(&creation).to!string );
			stdout.writef("    expiration time      : %s", ctime(&expiration).to!string );
			stdout.writefln("    filesystem name      : %s", filesystem);
		}	
		stdout.writefln("    available extensions : %d", extensions);
		if (verbose) {
			long rd = expiration - reminder/(24*3600);
			stdout.writef("    reminder             : %s", ctime(&rd).to!string );
			stdout.writefln("    mailaddress          : %s", mailaddress);
		}
	}
}


// implementations of legacy DB format from workspace++
class FilesystemDBV1 : Database {
private:
	Config config;
public:
	this(Config config) {
		this.config = config;
	}

	// return list of identifiers of DB entries matching pattern from filesystem or all valid filesystems
	//  does not check if request for "deleted" is valid, has to be done on caller side
	wsID[] matchPattern(string pattern, string filesystem, string user, string[] groups, bool deleted, bool groupworkspaces) {
		string filepattern;

		/* FIXME dead code? remove?
		string[] fslist ;
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
		*/

		// no access check with above core removed! has to happen on caller side!

		// list directory, this also reads YAML file in case of groupworkspaces
		string[] listdir(string pathname, string filepattern) {
			import std.algorithm;
			import std.array;
			import std.file;
			import std.path;

			debug {
			stdout.writefln("debug: listdir(%s, %s)",pathname, filepattern);
			}

			// in case of groupworkspace, read entry
			if (groupworkspaces) {
				auto filelist = std.file.dirEntries(pathname, filepattern, SpanMode.shallow).filter!(a => a.isFile);
				string[] list;
				foreach(f; filelist) {
					Node root;
					try {
						root = Loader.fromFile(f).load();
					} catch (dyaml.exception.YAMLException e) {
						stderr.writefln("error: yaml parser in file <%s>: %s", f, e.msg);
						continue;
					}
					string group = readValue!string(root, "group", ""); 	
					if (canFind(groups, group)) {
						list ~= f;
					}
				}	
				return list.map!(a => baseName(a)).array;
			} else {
				return std.file.dirEntries(pathname, filepattern, SpanMode.shallow)
					.filter!(a => a.isFile)
					.map!(a => baseName(a.name))
					.array;
			}

		}	

		// this has to happen here, as other DB might have different patterns
		if (groupworkspaces)
			filepattern = "*" ~ "-" ~ pattern;
		else
			filepattern = user ~ "-" ~ pattern;
		
		// helper to extract from filename the user-id part (assuming more is attached)
		wsID extractID(string fn) {
			auto pos=fn.indexOf('-');
			return wsID(fn[0..pos],fn[pos+1..$]);
		}
		
		// scan filesystem
		if (deleted) 
			return listdir(buildPath(config.database(filesystem),config.deleted(filesystem)), filepattern).
				map!(extractID).array;
		else 
			return listdir(config.database(filesystem), filepattern).
				map!(extractID).array;

	}

	// read DBentry and return it
	DBEntryV1 readEntry(string filesystem, string user, string id, bool deleted) {
		auto entry = new DBEntryV1;
		string filename;
		if (deleted) 
			filename = buildPath(config.database(filesystem), config.deleted(filesystem), user~"-"~id);
		else 
			filename = buildPath(config.database(filesystem), user~"-"~id);
		if (entry.readFromfile(id, filesystem, filename))
			return entry;
		else		
			return null;
	}
}
