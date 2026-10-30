// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_sequence.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetAppSequenceCollection on Isar {
  IsarCollection<AppSequence> get appSequences => this.collection();
}

const AppSequenceSchema = CollectionSchema(
  name: r'AppSequence',
  id: -8556943534974968238,
  properties: {
    r'lastProductNumber': PropertySchema(
      id: 0,
      name: r'lastProductNumber',
      type: IsarType.long,
    ),
    r'lastSyncAt': PropertySchema(
      id: 1,
      name: r'lastSyncAt',
      type: IsarType.dateTime,
    ),
    r'updatedAt': PropertySchema(
      id: 2,
      name: r'updatedAt',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _appSequenceEstimateSize,
  serialize: _appSequenceSerialize,
  deserialize: _appSequenceDeserialize,
  deserializeProp: _appSequenceDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _appSequenceGetId,
  getLinks: _appSequenceGetLinks,
  attach: _appSequenceAttach,
  version: '3.1.0+1',
);

int _appSequenceEstimateSize(
  AppSequence object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  return bytesCount;
}

void _appSequenceSerialize(
  AppSequence object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.lastProductNumber);
  writer.writeDateTime(offsets[1], object.lastSyncAt);
  writer.writeDateTime(offsets[2], object.updatedAt);
}

AppSequence _appSequenceDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = AppSequence();
  object.id = id;
  object.lastProductNumber = reader.readLong(offsets[0]);
  object.lastSyncAt = reader.readDateTimeOrNull(offsets[1]);
  object.updatedAt = reader.readDateTime(offsets[2]);
  return object;
}

P _appSequenceDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 2:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _appSequenceGetId(AppSequence object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _appSequenceGetLinks(AppSequence object) {
  return [];
}

void _appSequenceAttach(
    IsarCollection<dynamic> col, Id id, AppSequence object) {
  object.id = id;
}

extension AppSequenceQueryWhereSort
    on QueryBuilder<AppSequence, AppSequence, QWhere> {
  QueryBuilder<AppSequence, AppSequence, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension AppSequenceQueryWhere
    on QueryBuilder<AppSequence, AppSequence, QWhereClause> {
  QueryBuilder<AppSequence, AppSequence, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterWhereClause> idNotEqualTo(
      Id id) {
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

  QueryBuilder<AppSequence, AppSequence, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterWhereClause> idBetween(
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
}

extension AppSequenceQueryFilter
    on QueryBuilder<AppSequence, AppSequence, QFilterCondition> {
  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition> idBetween(
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

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastProductNumberEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastProductNumber',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastProductNumberGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastProductNumber',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastProductNumberLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastProductNumber',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastProductNumberBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastProductNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastSyncAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastSyncAt',
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastSyncAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastSyncAt',
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastSyncAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastSyncAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastSyncAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      lastSyncAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastSyncAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
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

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
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

  QueryBuilder<AppSequence, AppSequence, QAfterFilterCondition>
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

extension AppSequenceQueryObject
    on QueryBuilder<AppSequence, AppSequence, QFilterCondition> {}

extension AppSequenceQueryLinks
    on QueryBuilder<AppSequence, AppSequence, QFilterCondition> {}

extension AppSequenceQuerySortBy
    on QueryBuilder<AppSequence, AppSequence, QSortBy> {
  QueryBuilder<AppSequence, AppSequence, QAfterSortBy>
      sortByLastProductNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastProductNumber', Sort.asc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy>
      sortByLastProductNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastProductNumber', Sort.desc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> sortByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> sortByLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension AppSequenceQuerySortThenBy
    on QueryBuilder<AppSequence, AppSequence, QSortThenBy> {
  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy>
      thenByLastProductNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastProductNumber', Sort.asc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy>
      thenByLastProductNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastProductNumber', Sort.desc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> thenByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> thenByLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<AppSequence, AppSequence, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension AppSequenceQueryWhereDistinct
    on QueryBuilder<AppSequence, AppSequence, QDistinct> {
  QueryBuilder<AppSequence, AppSequence, QDistinct>
      distinctByLastProductNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastProductNumber');
    });
  }

  QueryBuilder<AppSequence, AppSequence, QDistinct> distinctByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncAt');
    });
  }

  QueryBuilder<AppSequence, AppSequence, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension AppSequenceQueryProperty
    on QueryBuilder<AppSequence, AppSequence, QQueryProperty> {
  QueryBuilder<AppSequence, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<AppSequence, int, QQueryOperations> lastProductNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastProductNumber');
    });
  }

  QueryBuilder<AppSequence, DateTime?, QQueryOperations> lastSyncAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncAt');
    });
  }

  QueryBuilder<AppSequence, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
