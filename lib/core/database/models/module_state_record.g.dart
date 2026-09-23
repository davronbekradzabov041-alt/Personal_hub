// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'module_state_record.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetModuleStateRecordCollection on Isar {
  IsarCollection<ModuleStateRecord> get moduleStateRecords => this.collection();
}

const ModuleStateRecordSchema = CollectionSchema(
  name: r'ModuleStateRecord',
  id: 1691539217480566290,
  properties: {
    r'enabled': PropertySchema(
      id: 0,
      name: r'enabled',
      type: IsarType.bool,
    ),
    r'installedAt': PropertySchema(
      id: 1,
      name: r'installedAt',
      type: IsarType.dateTime,
    ),
    r'installedVersion': PropertySchema(
      id: 2,
      name: r'installedVersion',
      type: IsarType.string,
    ),
    r'moduleId': PropertySchema(
      id: 3,
      name: r'moduleId',
      type: IsarType.string,
    ),
    r'state': PropertySchema(
      id: 4,
      name: r'state',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 5,
      name: r'updatedAt',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _moduleStateRecordEstimateSize,
  serialize: _moduleStateRecordSerialize,
  deserialize: _moduleStateRecordDeserialize,
  deserializeProp: _moduleStateRecordDeserializeProp,
  idName: r'id',
  indexes: {
    r'moduleId': IndexSchema(
      id: 294732126243497764,
      name: r'moduleId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'moduleId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _moduleStateRecordGetId,
  getLinks: _moduleStateRecordGetLinks,
  attach: _moduleStateRecordAttach,
  version: '3.1.0+1',
);

int _moduleStateRecordEstimateSize(
  ModuleStateRecord object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.installedVersion.length * 3;
  bytesCount += 3 + object.moduleId.length * 3;
  bytesCount += 3 + object.state.length * 3;
  return bytesCount;
}

void _moduleStateRecordSerialize(
  ModuleStateRecord object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.enabled);
  writer.writeDateTime(offsets[1], object.installedAt);
  writer.writeString(offsets[2], object.installedVersion);
  writer.writeString(offsets[3], object.moduleId);
  writer.writeString(offsets[4], object.state);
  writer.writeDateTime(offsets[5], object.updatedAt);
}

ModuleStateRecord _moduleStateRecordDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ModuleStateRecord();
  object.enabled = reader.readBool(offsets[0]);
  object.id = id;
  object.installedAt = reader.readDateTime(offsets[1]);
  object.installedVersion = reader.readString(offsets[2]);
  object.moduleId = reader.readString(offsets[3]);
  object.state = reader.readString(offsets[4]);
  object.updatedAt = reader.readDateTime(offsets[5]);
  return object;
}

P _moduleStateRecordDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _moduleStateRecordGetId(ModuleStateRecord object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _moduleStateRecordGetLinks(
    ModuleStateRecord object) {
  return [];
}

void _moduleStateRecordAttach(
    IsarCollection<dynamic> col, Id id, ModuleStateRecord object) {
  object.id = id;
}

extension ModuleStateRecordByIndex on IsarCollection<ModuleStateRecord> {
  Future<ModuleStateRecord?> getByModuleId(String moduleId) {
    return getByIndex(r'moduleId', [moduleId]);
  }

  ModuleStateRecord? getByModuleIdSync(String moduleId) {
    return getByIndexSync(r'moduleId', [moduleId]);
  }

  Future<bool> deleteByModuleId(String moduleId) {
    return deleteByIndex(r'moduleId', [moduleId]);
  }

  bool deleteByModuleIdSync(String moduleId) {
    return deleteByIndexSync(r'moduleId', [moduleId]);
  }

  Future<List<ModuleStateRecord?>> getAllByModuleId(
      List<String> moduleIdValues) {
    final values = moduleIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'moduleId', values);
  }

  List<ModuleStateRecord?> getAllByModuleIdSync(List<String> moduleIdValues) {
    final values = moduleIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'moduleId', values);
  }

  Future<int> deleteAllByModuleId(List<String> moduleIdValues) {
    final values = moduleIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'moduleId', values);
  }

  int deleteAllByModuleIdSync(List<String> moduleIdValues) {
    final values = moduleIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'moduleId', values);
  }

  Future<Id> putByModuleId(ModuleStateRecord object) {
    return putByIndex(r'moduleId', object);
  }

  Id putByModuleIdSync(ModuleStateRecord object, {bool saveLinks = true}) {
    return putByIndexSync(r'moduleId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByModuleId(List<ModuleStateRecord> objects) {
    return putAllByIndex(r'moduleId', objects);
  }

  List<Id> putAllByModuleIdSync(List<ModuleStateRecord> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'moduleId', objects, saveLinks: saveLinks);
  }
}

extension ModuleStateRecordQueryWhereSort
    on QueryBuilder<ModuleStateRecord, ModuleStateRecord, QWhere> {
  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension ModuleStateRecordQueryWhere
    on QueryBuilder<ModuleStateRecord, ModuleStateRecord, QWhereClause> {
  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterWhereClause>
      moduleIdEqualTo(String moduleId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'moduleId',
        value: [moduleId],
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterWhereClause>
      moduleIdNotEqualTo(String moduleId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'moduleId',
              lower: [],
              upper: [moduleId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'moduleId',
              lower: [moduleId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'moduleId',
              lower: [moduleId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'moduleId',
              lower: [],
              upper: [moduleId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension ModuleStateRecordQueryFilter
    on QueryBuilder<ModuleStateRecord, ModuleStateRecord, QFilterCondition> {
  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      enabledEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'enabled',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'installedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'installedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'installedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'installedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'installedVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'installedVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'installedVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'installedVersion',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'installedVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'installedVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'installedVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'installedVersion',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'installedVersion',
        value: '',
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      installedVersionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'installedVersion',
        value: '',
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'moduleId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'moduleId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'moduleId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'moduleId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'moduleId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'moduleId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'moduleId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'moduleId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'moduleId',
        value: '',
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      moduleIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'moduleId',
        value: '',
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'state',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'state',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'state',
        value: '',
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      stateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'state',
        value: '',
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterFilterCondition>
      updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ModuleStateRecordQueryObject
    on QueryBuilder<ModuleStateRecord, ModuleStateRecord, QFilterCondition> {}

extension ModuleStateRecordQueryLinks
    on QueryBuilder<ModuleStateRecord, ModuleStateRecord, QFilterCondition> {}

extension ModuleStateRecordQuerySortBy
    on QueryBuilder<ModuleStateRecord, ModuleStateRecord, QSortBy> {
  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByInstalledAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'installedAt', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByInstalledAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'installedAt', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByInstalledVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'installedVersion', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByInstalledVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'installedVersion', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByModuleId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'moduleId', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByModuleIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'moduleId', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'state', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'state', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension ModuleStateRecordQuerySortThenBy
    on QueryBuilder<ModuleStateRecord, ModuleStateRecord, QSortThenBy> {
  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByInstalledAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'installedAt', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByInstalledAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'installedAt', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByInstalledVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'installedVersion', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByInstalledVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'installedVersion', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByModuleId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'moduleId', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByModuleIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'moduleId', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'state', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'state', Sort.desc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension ModuleStateRecordQueryWhereDistinct
    on QueryBuilder<ModuleStateRecord, ModuleStateRecord, QDistinct> {
  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QDistinct>
      distinctByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'enabled');
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QDistinct>
      distinctByInstalledAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'installedAt');
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QDistinct>
      distinctByInstalledVersion({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'installedVersion',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QDistinct>
      distinctByModuleId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'moduleId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QDistinct> distinctByState(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'state', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ModuleStateRecord, ModuleStateRecord, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension ModuleStateRecordQueryProperty
    on QueryBuilder<ModuleStateRecord, ModuleStateRecord, QQueryProperty> {
  QueryBuilder<ModuleStateRecord, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ModuleStateRecord, bool, QQueryOperations> enabledProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'enabled');
    });
  }

  QueryBuilder<ModuleStateRecord, DateTime, QQueryOperations>
      installedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'installedAt');
    });
  }

  QueryBuilder<ModuleStateRecord, String, QQueryOperations>
      installedVersionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'installedVersion');
    });
  }

  QueryBuilder<ModuleStateRecord, String, QQueryOperations> moduleIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'moduleId');
    });
  }

  QueryBuilder<ModuleStateRecord, String, QQueryOperations> stateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'state');
    });
  }

  QueryBuilder<ModuleStateRecord, DateTime, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
