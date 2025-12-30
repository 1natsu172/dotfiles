function jdk
	set java_version $argv
	set -gx JAVA_HOME (/usr/libexec/java_home -v $java_version)
	java -version
end