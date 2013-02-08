thrift:
	mkdir -p generated
	thrift --gen cpp -o generated src/thrift/parquet.thrift 
	thrift --gen java -o generated src/thrift/parquet.thrift 
