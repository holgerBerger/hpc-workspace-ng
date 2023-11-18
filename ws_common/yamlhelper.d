//
// helpers to read config
//

import dyaml;
import config;

// read value of type T with key
T readValue(T)(Node root, string key, T defaultvalue) {
	if (root.containsKey(key)) 
		return root[key].get!T;
	else
		return defaultvalue;
}

@("readValue")
unittest {
	auto root = Loader.fromString("key: value\nintkey: -1\nverbose: true").load();
	// testing string value
	assert(readValue!string(root, "key", "") == "value");
	// testing default value
	assert(readValue!string(root, "keyless", "novalue") == "novalue");
	// testing int
	assert(readValue!int(root, "intkey", 0) == -1);
	// testing bool
	assert(readValue!bool(root, "verbose", false) == true);
}

// read array of type T  with key
T[] readArray(T)(Node root, string key) {
	// bail out if key does not exist
	if (!root.containsKey(key)) {
		return new T[0];
	}
	T[] array = new T[root[key].length];
	int i=0;
	foreach(Node n; root[key]) {
		array[i++]=n.get!T;
	}
	return array;
}

@("readarray")
unittest {
	auto root = Loader.fromString("ilist: [1,2,3]\nlist: [a,b,c]").load();
	// testing string value
	assert(readArray!string(root, "list") == ["a","b","c"]);
	// testing int value
	assert(readArray!int(root, "ilist") == [1,2,3]);
}
