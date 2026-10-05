class_name DataFile
## Reads the converter's binary files; the largest are gzip-compressed (`*.bin.gz`,
## tools/remake_import/common.py `gzipped`) to keep the builds small.


## The bytes of a converted file, decompressed when its name ends in `.gz` (empty when missing).
static func read(path: String) -> PackedByteArray:
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		if not FileAccess.file_exists(path):
			Log.error("DataFile: cannot read %s" % path)
		return data
	if path.ends_with(".gz"):
		return data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	return data
