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
import std.conv;
import config;
import dyaml;
import yamlhelper;
import core.stdc.time;
static import core.exception;

// tuple that identifies a workspace
//  background: list of workspaces for admins must also return user
struct WsId {
	string user;
	string id;
}

// interface to access the database
interface Database {
	// return list of entries 
	WsId[] matchPattern(const string pattern, const string filesystem, const string user, const string[] groups, 
																const bool deleted, const bool groupworkspaces);
	// TODO
	// read entry	
	DBEntry readEntry(in string filesystem, in string user, in string id, in bool deleted);
	void createEntry(in string filesystem, in string user, in string id, in string workspace, in long creation, 
		in long expiration, in long reminder, in int extensions, 
		in string group, in string mailaddress, in string comment);
	// write entry
	// expire entry
	// ...	
}

// interface for DBentry, allows printing and access for sorting
interface DBEntry {
	// print to stdout
	void print(const bool verbose, const bool terse);
	// sorting
	long getRemaining();
	string getId();
	long getCreation();
	string getWSPath();
}

// exception for errors in DB
class DBException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
		super(msg, file, line);
    }
}

