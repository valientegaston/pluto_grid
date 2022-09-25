import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:pluto_grid/pluto_grid.dart';

/*
  todo
    Column
      - Add
      - Hide
      - UnHide
    ColumnGroup
      - Apply changed depth when removing column
    Row
      - Move
      - Check
 */

abstract class IRowGroupState {
  bool get hasRowGroups;

  Iterable<PlutoRow> get iterateRootRowGroup;

  Iterable<PlutoRow> get iterateRowGroup;

  Iterable<PlutoRow> get iterateRowAndGroup;

  Iterable<PlutoRow> get iterateRow;

  bool isRootGroupedRow(PlutoRow row);

  bool isNotRootGroupedRow(PlutoRow row);

  bool isExpandedGroupedRow(PlutoRow row);

  bool isGroupedRowColumn(PlutoColumn column);

  void setRowGroupByColumns(
    List<PlutoColumn> columns, {
    bool notify = true,
  });

  void toggleExpandedRowGroup({
    required PlutoRow rowGroup,
    bool notify = true,
  });

  @protected
  void setRowGroupFilter(FilteredListFilter<PlutoRow>? filter);

  @protected
  void sortRowGroup({
    required PlutoColumn column,
    required int Function(PlutoRow, PlutoRow) compare,
  });

  @protected
  void addRowGroup(List<PlutoRow> rows);

  @protected
  void removeRowAndGroupByKey(Iterable<Key> keys);

  @protected
  void removeColumnsInRowGroup(
    List<PlutoColumn> columns, {
    bool notify = true,
  });
}

mixin RowGroupState implements IPlutoGridState {
  @override
  bool get hasRowGroups => _rowGroupColumns.isNotEmpty;

  List<PlutoColumn> _rowGroupColumns = [];

  PlutoColumn? get _rootRowGroupColumn => _rowGroupColumns.firstOrNull;

  @override
  Iterable<PlutoRow> get iterateRootRowGroup sync* {
    if (!hasRowGroups) {
      return;
    }

    for (final row in refRows.originalList.where(isRootGroupedRow)) {
      yield row;
    }
  }

  @override
  Iterable<PlutoRow> get iterateRowGroup sync* {
    if (!hasRowGroups) {
      return;
    }

    for (final row in _iterateRowGroup(iterateRootRowGroup)) {
      yield row;
    }
  }

  @override
  Iterable<PlutoRow> get iterateRowAndGroup sync* {
    for (final row in hasRowGroups
        ? _iterateRowAndGroup(iterateRootRowGroup)
        : refRows.originalList) {
      yield row;
    }
  }

  @override
  Iterable<PlutoRow> get iterateRow sync* {
    for (final row in hasRowGroups
        ? _iterateRow(iterateRootRowGroup)
        : refRows.originalList) {
      yield row;
    }
  }

  @override
  bool isRootGroupedRow(PlutoRow row) {
    if (!row.type.isGroup) {
      return false;
    }

    return row.type.group.groupField == _rootRowGroupColumn?.field;
  }

  @override
  bool isNotRootGroupedRow(PlutoRow row) => !isRootGroupedRow(row);

  @override
  bool isExpandedGroupedRow(PlutoRow row) {
    return row.type.isGroup && row.type.group.expanded;
  }

  @override
  bool isGroupedRowColumn(PlutoColumn column) {
    return _rowGroupColumns.firstWhereOrNull((c) => c.field == column.field) !=
        null;
  }

  @override
  void setRowGroupByColumns(
    List<PlutoColumn> columns, {
    bool notify = true,
  }) {
    final List<PlutoRow> groupedRows = columns.isEmpty
        ? iterateRow.toList()
        : PlutoRowGroupHelper.toGroupByColumns(
            columns: columns,
            rows: iterateRow,
          );

    refRows.clearFromOriginal();

    refRows.addAll(groupedRows);

    _rowGroupColumns = columns;

    if (isPaginated) {
      resetPage(resetCurrentState: true, notify: false);
    }

    if (notify) {
      notifyListeners();
    }
  }

  @override
  void toggleExpandedRowGroup({
    required PlutoRow rowGroup,
    bool notify = true,
  }) {
    assert(hasRowGroups);

    if (!rowGroup.type.isGroup) {
      return;
    }

    if (rowGroup.type.group.expanded) {
      final Set<Key> removeKeys = {};

      addChildToCollapse(PlutoRow row) {
        for (final child in row.type.group.children) {
          removeKeys.add(child.key);
          if (child.type.isGroup) {
            addChildToCollapse(child);
          }
        }
      }

      addChildToCollapse(rowGroup);

      refRows.removeWhereFromOriginal((e) => removeKeys.contains(e.key));
    } else {
      final List<PlutoRow> addRows = [];

      addChildToExpand(PlutoRow row) {
        for (final child in row.type.group.children) {
          addRows.add(child);
          if (child.type.isGroup && child.type.group.expanded) {
            addChildToExpand(child);
          }
        }
      }

      addChildToExpand(rowGroup);

      final idx = refRows.indexOf(rowGroup);

      refRows.insertAll(idx + 1, addRows);
    }

    rowGroup.type.group.setExpanded(!rowGroup.type.group.expanded);

    if (isPaginated) {
      resetPage(resetCurrentState: false, notify: false);
    }

    updateCurrentCellPosition(notify: false);

    clearCurrentSelecting(notify: false);

    if (notify) {
      notifyListeners();
    }
  }

  @override
  @protected
  void setRowGroupFilter(FilteredListFilter<PlutoRow>? filter) {
    assert(hasRowGroups);

    _ensureRowGroups(() {
      if (filter == null) {
        void setFilter(FilteredList<PlutoRow> filteredList) {
          filteredList.setFilter(null);

          if (filteredList.originalList.isEmpty ||
              !filteredList.originalList.first.type.isGroup) {
            return;
          }

          for (final c in filteredList.originalList) {
            setFilter(c.type.group.children);
          }
        }

        setFilter(refRows);
      } else {
        void setFilter(FilteredList<PlutoRow> filteredList) {
          filteredList.setFilter((row) {
            if (!row.type.isGroup) {
              return filter(row);
            }

            setFilter(row.type.group.children);
            return row.type.group.children.filterOrOriginalList.isNotEmpty;
          });
        }

        setFilter(refRows);
      }
    });
  }

  @override
  @protected
  void sortRowGroup({
    required PlutoColumn column,
    required int Function(PlutoRow, PlutoRow) compare,
  }) {
    assert(hasRowGroups);

    _ensureRowGroups(() {
      if (refRows.originalList.isEmpty) {
        return;
      }

      if (refRows.originalList.first.type.group.groupField == column.field) {
        refRows.sort(compare);

        return;
      }

      sortChildren(PlutoRow row) {
        assert(row.type.isGroup);

        if (row.type.group.childrenGroupField == column.field ||
            !row.type.group.children.originalList.first.type.isGroup) {
          row.type.group.children.sort(compare);

          return;
        }

        if (row.type.group.children.originalList.first.type.isGroup) {
          for (final child in row.type.group.children.originalList) {
            sortChildren(child);
          }
        }
      }

      for (final row in refRows.originalList) {
        sortChildren(row);
      }
    });
  }

  @override
  @protected
  void addRowGroup(List<PlutoRow> rows) {
    assert(hasRowGroups);

    final grouped = PlutoRowGroupHelper.toGroupByColumns(
      columns: _rowGroupColumns,
      rows: rows,
    );

    _ensureRowGroups(() {
      addAll(Iterable<PlutoRow> groupedRows, FilteredList<PlutoRow> ref) {
        for (final row in groupedRows) {
          final found = ref.originalList.firstWhereOrNull(
            (e) => e.key == row.key,
          );

          if (found == null) {
            ref.add(row);
          } else {
            if (found.type.group.children.originalList.first.type.isGroup) {
              addAll(row.type.group.children, found.type.group.children);
            } else {
              found.type.group.children.addAll(row.type.group.children);
            }
          }
        }
      }

      addAll(grouped, refRows);
    });
  }

  @override
  @protected
  void removeRowAndGroupByKey(Iterable<Key> keys) {
    assert(hasRowGroups);

    _ensureRowGroups(() {
      bool removeAll(PlutoRow row) {
        if (row.type.isGroup) {
          row.type.group.children.removeWhereFromOriginal(removeAll);
          if (row.type.group.children.originalList.isEmpty) {
            return true;
          }
        }
        return keys.contains(row.key);
      }

      refRows.removeWhereFromOriginal(removeAll);
    });
  }

  @override
  @protected
  void removeColumnsInRowGroup(
    List<PlutoColumn> columns, {
    bool notify = true,
  }) {
    if (_rowGroupColumns.isEmpty || columns.isEmpty) {
      return;
    }

    final Set<Key> removeKeys = Set.from(columns.map((e) => e.key));

    isNotRemoved(e) => !removeKeys.contains(e.key);

    final remaining = _rowGroupColumns.where(isNotRemoved);

    if (remaining.length == _rowGroupColumns.length) {
      return;
    }

    setRowGroupByColumns(
      remaining.toList(growable: false),
      notify: notify,
    );
  }

  Iterable<PlutoRow> _iterateRow(Iterable<PlutoRow> rows) sync* {
    for (final row in rows) {
      if (row.type.isGroup) {
        for (final child in _iterateRow(row.type.group.children.originalList)) {
          yield child;
        }
      } else {
        yield row;
      }
    }
  }

  Iterable<PlutoRow> _iterateRowGroup(Iterable<PlutoRow> rows) sync* {
    for (final row in rows) {
      if (row.type.isGroup) {
        yield row;
        for (final child
            in _iterateRowGroup(row.type.group.children.originalList)) {
          yield child;
        }
      }
    }
  }

  Iterable<PlutoRow> _iterateRowAndGroup(Iterable<PlutoRow> rows) sync* {
    for (final row in rows) {
      yield row;
      if (row.type.isGroup) {
        for (final child
            in _iterateRowAndGroup(row.type.group.children.originalList)) {
          yield child;
        }
      }
    }
  }

  void _ensureRowGroups(void Function() callback) {
    assert(hasRowGroups);

    _collapseAllRowGroup();

    callback();

    _restoreExpandedRowGroup();
  }

  void _collapseAllRowGroup() {
    refRows.removeWhereFromOriginal(isNotRootGroupedRow);
  }

  void _restoreExpandedRowGroup() {
    final Iterable<PlutoRow> expandedRows = refRows.filterOrOriginalList
        .where(isExpandedGroupedRow)
        .toList(growable: false);

    bool toResetPage = false;

    if (isPaginated) {
      refRows.setFilterRange(null);
      toResetPage = true;
    }

    for (final rowGroup in expandedRows) {
      final List<PlutoRow> addRows = [];

      addExpandedChildren(PlutoRow row) {
        if (row.type.group.expanded) {
          for (final child in row.type.group.children) {
            addRows.add(child);
            if (child.type.isGroup && child.type.group.expanded) {
              addExpandedChildren(child);
            }
          }
        }
      }

      addExpandedChildren(rowGroup);

      final idx = refRows.filterOrOriginalList.indexOf(rowGroup);

      refRows.insertAll(idx + 1, addRows);
    }

    if (toResetPage) {
      resetPage(resetCurrentState: false, notify: false);
    }
  }
}

class PlutoRowGroupHelper {
  static List<PlutoRow> toGroupByColumns({
    required List<PlutoColumn> columns,
    required Iterable<PlutoRow> rows,
  }) {
    assert(columns.isNotEmpty);
    assert(rows.isNotEmpty);

    final maxDepth = columns.length;
    int sortIdx = 0;

    List<PlutoRow> toGroup({
      required Iterable<PlutoRow> children,
      required int depth,
      String? previousKey,
    }) {
      final groupedColumn = columns[depth];

      return groupBy<PlutoRow, String>(children, (row) {
        return row.cells[columns[depth].field]!.value.toString();
      }).entries.map(
        (group) {
          final groupKey =
              previousKey == null ? group.key : '${previousKey}_${group.key}';

          final Key key = ValueKey(
            '${groupedColumn.field}_${groupKey}_rowGroup',
          );

          final nextDepth = depth + 1;

          final firstRow = group.value.first;

          final cells = <String, PlutoCell>{};

          final row = PlutoRow(
            cells: cells,
            key: ValueKey(key),
            sortIdx: sortIdx++,
            type: PlutoRowType.group(
              groupField: groupedColumn.field,
              children: FilteredList(
                initialList: nextDepth < maxDepth
                    ? toGroup(
                        children: group.value,
                        depth: nextDepth,
                        previousKey: groupKey,
                      ).toList()
                    : group.value.toList(),
              ),
            ),
          );

          for (var e in firstRow.cells.entries) {
            cells[e.key] = PlutoCell(
              value: columns.firstWhereOrNull((c) => c.field == e.key) != null
                  ? e.value.value
                  : null,
              key: ValueKey('${key}_${e.key}_cell'),
            )
              ..setColumn(e.value.column)
              ..setRow(row);
          }

          return row;
        },
      ).toList();
    }

    return toGroup(children: rows, depth: 0);
  }
}