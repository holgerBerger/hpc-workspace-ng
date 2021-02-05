//
// configuration class with helpers to extract information
//

import std.stdio;
import std.algorithm : canFind;
import std.array : array;
import dyaml;
import options;
import db;
import dbv1;
import yamlhelper;


// config of filesystem, part of global config
struct Filesystem_config {
	string name;			// name of filesystem
	string[] spaces;		// prefix path in filesystem for workspaces
	string deleted;			// subdirectory to move deleted workspaces to, relative path
	string database;		// path to workspace db for this filesystem
	string[] groupdefault;		// groups having this filesystem as default
	string[] userdefault;		// users having this filesytem as default
	string[] user_acl;		// if present, users have to match ACL, user or +user grant access, -user denies
	string[] group_acl;		// if present, users have to match ACL
	int keeptime;			// max time in days to keep deleted workspace
	int maxduration;		// max duration a user can choose for this filesystem
	int maxextensions;		// max extensiones a user can do for this filesystem
	// migration helpers
	bool allocatable;		// is this filesystem allocatable? (or read only?) 
	bool extendable;		// is this filesystem extendable? (or read only?)
	bool restorable;		// can a workspace be restored into this filesystem?
}

// global config, glocal settings + workspaces
class Config {
private:
	// global settings
	string clustername;		// name of cluster for mails
	string smtphost;		// smtp host for sending mails
	string mail_from;		// sender for mails
	string default_workspace;	// workspace to use if several are allowed
	int duration;			// max duration user can choose
	int reminderdefault;		// when to send a reminder, 0 no default reminder
	int maxextensions;		// max extensions a user gets
	int dbuid;			// uid of DB user
	int dbgid;			// gid of DB user
	string[] admins;		// people allowed to see all workspaces
	Filesystem_config[string] filesystems;	// list of workspace filesystems

	// copy of opts for local use
	Options opts;

public:
	//
	// constructors
	//

	// read config file into config structure
	this(in string filename, Options opts) {
		Node root;
		this.opts = opts;
		root = Loader.fromFile(filename).load();
		if (opts.debugflag) {
			writeln("reading configuration file <", filename,">");
		}
		readYAML(root);
	}

	// read config from provided yaml node
	this(Node root, Options opts) {
		this.opts = opts;
		readYAML(root);
	}

	version(unittest)
	this() {
	}

	// read YAML from node into config class
	private void readYAML(Node root) {
		// FIXME this prevents multiple config files, should not overwrite previous values
		// this would be ok if this is old style reade only used for first file and addition files	
		// would be read with additional reader

		// global flags
		clustername = readValue!string(root, "clustername", "");
		smtphost = readValue!string(root, "smpthost", "");
		mail_from = readValue!string(root, "mail_from", "");
		default_workspace = readValue!string(root, "default", "");
		duration = readValue!int(root, "duration", 30);
		reminderdefault = readValue!int(root, "reminderdefault", -1);
		maxextensions = readValue!int(root, "maxextensions", 100);
		dbuid = readValue!int(root, "dbuid", -1);
		dbgid = readValue!int(root, "dbgid", -1); 
		admins = readArray!string(root, "admins");	

		// loops over filesystems if any in file
		if (root.containsKey("filesystems") || root.containsKey("workspaces")) {
			// we handle "filesystem" or "workspaces" here for compatibility
			Node[] fslist;
			if (root.containsKey("filesystems")) fslist ~= root["filesystems"].mappingKeys().array;
			if (root.containsKey("workspaces"))  fslist ~= root["workspaces"].mappingKeys().array;
			
			foreach(fs; fslist) {
				auto fsname = fs.get!string;
				Node cnode;
				// we handle "filesystem" or "workspaces" here for compatibility
				try {
					cnode = root["filesystems"][fs.get!string];
				} 
				catch(Throwable) {
					cnode = root["workspaces"][fs.get!string];
				}
				// read current workspace
				Filesystem_config cfs;
				cfs.name = fsname;
				cfs.database = readValue!string(cnode, "database", "");
				cfs.deleted = readValue!string(cnode, "deleted", "");
				cfs.keeptime = readValue!int(cnode, "keeptime", 10);
				cfs.maxduration = readValue!int(cnode, "maxduration", -1);
				cfs.maxextensions = readValue!int(cnode, "maxextensions", -1);
				cfs.allocatable = readValue!bool(cnode, "allocatable", true);
				cfs.extendable = readValue!bool(cnode, "extendable", true);
				cfs.restorable = readValue!bool(cnode, "restorable", true);
				cfs.spaces = readArray!string(cnode, "spaces");
				cfs.groupdefault = readArray!string(cnode, "groupdefault");
				cfs.userdefault = readArray!string(cnode, "userdefault");
				cfs.user_acl = readArray!string(cnode, "user_acl");
				cfs.group_acl = readArray!string(cnode, "group_acl");
				filesystems[fsname] = cfs;
			}
		}
	}
	

	// TODO basic validator, like: any filesystems at all? dbuid/dbgid set?

	// TODO reader for additional files


	// 
	// checks and extractors for this config
	//

	// get list of valid filesystems for given user, each filesystem is only once in the list
	// SPEC: validFilesystems(user)
	// SPEC: this list is sorted: userdefault, groupdefault, global default, others
	// SPEC:CHANGE: a user has to be able to access global default filesystem, otherwise it will be not returned here 
	// SPEC:CHANGE: a user or group acl can contain a username with - prefixed, to disallow access	
	// SPEC:CHANGE: a user or group acl can contain a username with + prefix, to allow access, same as only listing user/group
	// SPEC: as soon as an ACL exists, access is denied to those not in ACL
	// SPEC: user acls are checked after groups for - entries, so users can be excluded after having group access
	// SPEC:CHANGE: a user default does not override an ACL
	// SPEC: admins have access to all filesystems
	string[] validFilesystems(string user, string[] groups) {
		string[] validfs;

		if (opts.debugflag) stderr.writefln("validFilesystems(%s,%s) over %s",user,groups,filesystems.keys);

		if ((default_workspace != "") && hasAccess(user, groups, default_workspace) ) {
			if (opts.debugflag) stderr.writefln("  adding default_workspace <%s>", default_workspace);
			validfs ~= default_workspace;
		}

		// check if group or user default, user first
		// SPEC: with users first a workspace with user default is always in front of a groupdefault
		foreach(string fs; filesystems.keys) {
			if (canFind(filesystems[fs].userdefault, user)) {
				if (opts.debugflag) stderr.writefln("  checking if userdefault <%s> already added", fs);
				if (hasAccess(user, groups, fs) && !canFind(validfs, fs)) {
					if (opts.debugflag) stderr.writefln("    adding userdefault <%s>", fs);
					validfs ~= fs;
				}
			}
		}	

		// now groups
		foreach(string fs; filesystems.keys) {
			foreach(string group; groups) {
				if (opts.debugflag) stderr.writefln("  checking if groupdefault <%s> already added", fs);
				if (canFind(filesystems[fs].groupdefault, group)) {
					if (hasAccess(user, groups, fs) && !canFind(validfs, fs)) {
						if (opts.debugflag) stderr.writefln("    adding groupdefault <%s>", fs);
						validfs ~= fs;
					}
				}
			}
		}	

		// now again all with access
		foreach(string fs; filesystems.keys) {
			if (hasAccess(user, groups, fs) && !canFind(validfs, fs)) {
				if (opts.debugflag) stderr.writefln("    adding as having access <%s>", fs);
				validfs ~= fs;
			}
		}	

		if (opts.debugflag) stderr.writefln(" => valid filesystems %s", validfs);

		return validfs;					
	}


	unittest{
		auto root = Loader.fromString(	"default: third\n" ~
						"workspaces:\n" ~
						"  first:\n"~
						"    user_acl: [+a,-b,d]\n"~
						"    groupdefault: [gb]\n"~
						"filesystems:\n" ~    // test if filesystem and workspaces works
						"  second:\n"~
						"    userdefault: [a]\n"~
						"  third:\n"~
						"    userdefault: [z,y]\n"~
						"\n").load();

		auto config = new Config(root, new Options( ["" /* ,"--debug" */ ] ));

		// see if default is respected
		assert(config.validFilesystems("c",[]) == ["third","second"]);
		// see if userdefault and acl works
		assert(config.validFilesystems("a",[]) == ["third","second","first"]);
		// see if ACL works, default does not override ACL
		assert(config.validFilesystems("b",["gb"]) == ["third","second"]);
		// global, groupdefault, others
		assert(config.validFilesystems("d",["gb"]) == ["third","first","second"]);

		auto root2 = Loader.fromString(	"admins: [d]\n" ~
						"workspaces:\n" ~
						"  first:\n"~
						"    user_acl: [+a,-b,d]\n"~
						"    groupdefault: [gb]\n"~
						"filesystems:\n" ~    // test if filesystem and workspaces works
						"  second:\n"~
						"    userdefault: [a]\n"~
						"  third:\n"~
						"    userdefault: [z,y]\n"~
						"\n").load();

		auto config2 = new Config(root2, new Options( ["" /* ,"--debug" */ ] ));

		// global, groupdefault, others
		assert(config2.validFilesystems("d",["gb"]) == ["first","second","third"]);
		// userdefault first, group second, multiple groups
		assert(config2.validFilesystems("a",["gc","gb"]) == ["second","first","third"]);
		// user first, others, no denied, not only for first user, multiple groups
		assert(config2.validFilesystems("y",["ga","gc"]) == ["third","second"]);
		// admin user check, sees all filesystems
		assert(config2.validFilesystems("d",[]) == ["second", "third", "first"]);
	}




	// check if given user can assess given filesystem with current config
	//  see validFilesystems for specification of ACLs
	bool hasAccess(string user, string[] groups, string filesystem) {
		bool ok = true;

		if (opts.debugflag) stderr.writefln("hasAccess(%s,%s,%s)",user,groups,filesystem);

		// see if FS is valid
		if ( !(filesystem in filesystems) ) {
			stderr.writeln("error: invalid filesystem queried for access: ", filesystem);
			return false;
		}

		// check ACLs, group first, user second to allow -user to override group grant
		if (filesystems[filesystem].user_acl.length>0 || filesystems[filesystem].group_acl.length>0) {
			// as soon as any ACL is presents, access is denied and has to be granted
			ok = false;
			if (opts.debugflag) stdout.writeln("  ACL present, access denied");

			if (filesystems[filesystem].group_acl.length>0) {
				if (opts.debugflag) stderr.write("    group ACL present,");
				foreach(string group ; groups) {
					if (canFind(filesystems[filesystem].group_acl, group)) ok = true;
					if (canFind(filesystems[filesystem].group_acl, "+"~group)) ok = true;
					if (canFind(filesystems[filesystem].group_acl, "-"~group)) ok = false;
					if (opts.debugflag) stderr.writeln("    access ", ok?"granted":"denied");
				}
			}
			
			if (filesystems[filesystem].user_acl.length>0) {
				if (opts.debugflag) stderr.write("    user ACL present, ");
				if (canFind(filesystems[filesystem].user_acl, user)) ok = true;
				if (canFind(filesystems[filesystem].user_acl, "+"~user)) ok = true;
				if (canFind(filesystems[filesystem].user_acl, "-"~user)) ok = false;
				if (opts.debugflag) stderr.writeln("    access ", ok?"granted":"denied");
			}
		}

		// check admins list, admins can see and access all filesystems
		if (admins.length>0) {
			if (opts.debugflag) stderr.write("    admin list present, ");
			if (canFind(admins, user)) ok = true;
			if (opts.debugflag) stderr.writeln("    access ", ok?"granted":"denied");
		}

		if (opts.debugflag) stderr.writefln(" => access to <%s> for user <%s> %s", filesystem, user, ok?"granted":"denied");

		return ok;
	}

	unittest{
		auto root = Loader.fromString(	"admins: [d]\n" ~
						"workspaces:\n" ~
						"  testacl:\n"~
						"    spaces: []\n"~
						"    user_acl: [+a,-b]\n"~
						"    group_acl: [+bg]\n"~
						"filesystems:\n" ~    // test if filesystem and workspaces works
						"  testnoacl:\n"~
						"    spaces: []\n"~
						"\n").load();

		auto config = new Config(root, new Options( ["" /*,"--debug"*/ ] ));

		// workspace no acl
		assert(config.hasAccess("a",["cg","dg"],"testnoacl") == true);
		// workspace with acl, through user
		assert(config.hasAccess("a",["cg","dg"],"testacl") == true);
		// workspace with acl, unknown user
		assert(config.hasAccess("c",[],"testacl") == false);
		// workspace with acl, through group
		assert(config.hasAccess("c",["bg"],"testacl") == true);
		// workspace with acl, through group but forbidden as user
		assert(config.hasAccess("b",["bg"],"testacl") == false);
		// admin user
		assert(config.hasAccess("d",[""],"testacl") == true);
	}

	// geter for database id
	string database(string filesystem) {
		// FIXME error check if filesystem exists
		return filesystems[filesystem].database;
	}

	// geter for database id
	string deleted(string filesystem) {
		// FIXME error check if filesystem exists
		return filesystems[filesystem].deleted;
	}

	// is user admin?
	bool isAdmin(string user) {
		return canFind(admins, user);
	}			

	// get DB matching the DB type of the config
	Database OpenDB() {
		// FIXME check database string for file:// pattern, if no : assume file
		return new FilesystemDBV1(this);
	}

}
