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

// interface for DBentry, allows printing and access for sorting
interface DBEntry {
	void print(bool verbose, bool terse);
	long getRemaining();
	string getId();
	long getCreation();
}


