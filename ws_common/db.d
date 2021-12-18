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


// tuple that identifies a workspace
//  background: list of workspaces for admins must also return user
struct wsID {
	string user;
	string id;
}

// interface to access the database
interface Database {
	// return list of entries 
	wsID[] matchPattern(const string pattern, const string filesystem, const string user, const string[] groups, const bool deleted, const bool groupworkspaces);
	// TODO
	// read entry	
	DBEntry readEntry(const string filesystem, const string user, const string id, const bool deleted);
	void createEntry(const string filesystem, const string user, const string id, const string workspace, const long creation, 
		const long expiration, const long reminder, const int extensions, 
		const string group, const string mailaddress, const string comment);
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
}


