
package Bio::DB::Tree::Store::DBI::SQLite;

use strict;
use DBI qw(:sql_types);
use Cwd 'abs_path';
use File::Spec;
use base qw(Bio::DB::Tree::Store);


###
# object initialization
#
sub init {
  my $self          = shift;
  my ($dsn,
      $is_temporary,
      $autoindex,
      $dump_dir,
      $user,
      $pass,
      $dbi_options,
      $writeable,
      $create,
     ) = $self->_rearrange([qw(DSN TEMPORARY AUTOINDEX DUMPDIR
			       USER PASS OPTIONS WRITE
			       CREATE)
			   ],@_);
  $dbi_options  ||= {};
  $writeable    = 1 if $is_temporary or $dump_dir;
  $dsn or $self->throw("Usage: ".__PACKAGE__."->init(-dsn => \$dbh || \$dsn)");

  my $dbh;
  if (ref $dsn) {
    $dbh = $dsn;
  } else {
    $dsn = "dbi:SQLite:$dsn" unless $dsn =~ /^dbi:/;
    $dbh = DBI->connect($dsn,$user,$pass,$dbi_options) or $self->throw($DBI::errstr);
    $dbh->do("PRAGMA synchronous = OFF;"); # makes writes much faster
    $dbh->do("PRAGMA temp_store = MEMORY;"); # less disk I/O; some speedup
    $dbh->do("PRAGMA cache_size = 20000;"); # less disk I/O; some speedup
  }
  $self->{dbh}       = $dbh;
  $self->{is_temp}   = $is_temporary;
  $self->{writeable} = $writeable;

#  $self->default_settings;
#  $self->autoindex($autoindex)                   if defined $autoindex;
#  $self->dumpdir($dump_dir)                      if $dump_dir;
  if ($self->is_temp) {
    $self->init_tmp_database();
  } elsif ($create) {
    $self->init_database('erase');
  }
}

sub table_definitions {
  my $self = shift;
  my $defs =
    {
     tree => <<END,
(
       tree_id integer primary key autoincrement,
       label text not null,
       is_rooted integer default 1,
       root_id integer not null,
       annotations text
);
create unique index ui_tree_id on tree(tree_id);
create index i_root_node_id ON tree(root_id);
create index i_treelabel on tree(label);
create index i_rooted on tree(is_rooted);
END

     node => <<END,
(
       node_id integer primary key autoincrement,
       parent_id integer,
       label text,
       distance_to_parent real,
       annotations text,
       left_idx integer,
       right_idx integer
);
create index ui_nodeid ON node (node_id);
create index i_nodelabel ON node (label);
create index i_leftidx ON node (left_idx);
create index i_rightidx ON node (right_idx);

END
    };
  return $defs;
}

=head2 Node methods

=cut

=head2 insert_node

 Title   : insert_node
 Usage   : $dbkey = $store->insert_node($nodeh, $parent);

 Function: Inserts a single node into the underlying storage. The
           default assumption is that the node does not exist yet,
           however the database defines (and/or enforces) that.

 Example :
 Returns : If successful, the primary key of the node that has been created. 

 Args :    The node to be inserted as a hashref or a Bio::Tree::NodeI
           object, and the parent as a primary key or a
           Bio::DB::Tree::Node object.

           If the node ia a hashref, the key '-parent' may be used to
           provide the primary key to the parent node instead of a
           second argument, and the key '-tree' to provide the primary
           key to the tree of which this node is part.  Depending on
           the backing database, the parent and/or the tree may be
           optional (and may be provided later through an update).

=cut

sub insert_node {
    my $self = shift;
    my ($nodeh, $parent) = @_;

    # unify the parent from the different ways it can be provided
    if (ref($parent)) {
        $parent = $parent->node_id();
    } elsif (!defined($parent)) {
        $parent = $nodeh->{'-parent'} if exists($nodeh->{'-parent'});
    }
    
    # unify between node object or hashref
    my $data = $self->_node_to_hash($nodeh);

    # store in database
    my $sth = $self->{'_sths'}->{'insertNode'};
    if (! $sth) {
        $sth = $self->_prepare(
            "INSERT INTO node (parent_id,label,distance_to_parent,annotations)"
            ." VALUES (?,?,?,?)");
        $self->{'_sths'}->{'insertNode'} = $sth;
    }
    $sth->execute($parent, 
                  $data->{'-id'}, $data->{'-branch_length'}, 
                  $data->{'-flatAnnotations'});
    my $pk = $self->dbh->func('last_insert_rowid');
    $nodeh->node_id($pk) if $pk && $nodeh->isa("Bio::DB::Tree::Node");
    # done
    return $pk;
}

=head2 _node_to_hash

 Title   : _node_to_hash
 Usage   : $nodeHash = $self->_node_to_hash($nodeObj);
 Function: Unifies a hashref and node object representation to a
           hashref representation. This will also flatten out the
           key-value annotations.

 Example :
 Returns : A hashref with the standard keys set if the input object
           had a value for them, and with the flattened annotations
           under the -flatAnnotations key if the input object had
           annotations. If the input object was a hashref, the
           returned ref will have at least all keys that the input ref
           had.
 Args :    A hashref of node attribute names and their values, or a
           Bio::Tree::NodeI object.

=cut

sub _node_to_hash {
    my $self = shift;
    my $obj = shift;

    # unify the hashref and object options to a single format
    my $h;
    if ($obj->isa("Bio::Tree::NodeI")) {
        $h = {};
        # flatten out all key-value annotations (if we have any)
        my $flatAnnots = _flatten_annotations($obj);
        $h->{'-flatAnnotations'} = $flatAnnots if $flatAnnots;
        $h->{'-id'} = $obj->id if $obj->id;
        $h->{'-branch_length'} = $obj->branch_length if $obj->branch_length();
        if ($obj->isa("Bio::DB::Tree::Node")) {
            $h->{'-pk'} = $obj->node_id;
            #can't do this right now - would trigger a recursive insert:
            # $h->{'-parent'} = $obj->parent_id if $obj->parent_id;
        }
    } else {
        $h = {%$obj};
        # flatten out all key-value annotations (if we have any)
        my $flatAnnots = _flatten_keyvalues($obj->{'-annotations'});
        $h->{'-flatAnnotations'} = $flatAnnots if $flatAnnots;
    }
    return $h;
}

=head2 _tree_to_hash

 Title   : _tree_to_hash
 Usage   : $treeHash = $self->_tree_to_hash($treeObj);
 Function: Unifies a hashref and tree object representation to a
           hashref representation. This will also flatten out the
           key-value annotations.

 Example :
 Returns : A hashref with the standard keys set if the input object
           had a value for them, and with the flattened annotations
           under the -flatAnnotations key if the input object had
           annotations. If the input object was a hashref, the
           returned ref will have at least all keys that the input ref
           had.
 Args :    A hashref of tree attribute names and their values, or a
           Bio::Tree::TreeI object.

=cut

sub _tree_to_hash {
    my $self = shift;
    my $obj = shift;

    # unify the hashref and object options to a single format
    my $h;
    if ($obj->isa("Bio::Tree::TreeI")) {
        $h = {};
        # flatten out all key-value annotations (if we have any)
        my $flatAnnots = _flatten_annotations($obj);
        $h->{'-flatAnnotations'} = $flatAnnots if $flatAnnots;
        $h->{'-id'} = $obj->id if $obj->id;
        $h->{'-branch_length'} = $obj->branch_length if $obj->branch_length();
        if ($obj->isa("Bio::DB::Tree::Node")) {
            $h->{'-pk'} = $obj->node_id;
            #can't do this right now - would trigger a recursive insert:
            # $h->{'-parent'} = $obj->parent_id if $obj->parent_id;
        }
    } else {
        $h = {%$obj};
        # flatten out all key-value annotations (if we have any)
        my $flatAnnots = _flatten_keyvalues($obj->{'-annotations'});
        $h->{'-flatAnnotations'} = $flatAnnots if $flatAnnots;
    }
    return $h;
}

sub _create_node {
  my $self = shift;
  my ($parent,$label,$branchlen,$annotations) = @_;
  my $sth = $self->_prepare(<<END);
INSERT INTO node (node_id,parent_id,label,distance_to_parent,annotations) VALUES (?,?,?,?,?)
END
  $sth->execute(undef,$parent,$label, $branchlen,$annotations);
  $sth->finish;
  return Bio::DB::Tree::Node->new(-node_id => $self->dbh->func('last_insert_rowid'),
				  -store   => $self);

}

=head2 update_node

 Title   : update_node
 Usage   : $store->update_node($nodeh, $parent);

 Function: Updates a single node in the underlying storage. The node
           must exist already.

 Example :
 Returns : True if success and false otherwise.

 Args :    The node data to which the database is to be updated as a
           hashref or a Bio::DB::Tree::Node object that has been
           obtained from this store, and the parent as a primary key
           to the parent node or also as a Bio::DB::Tree::Node
           object. The parent is optional if it is not being updated.

           If the node is a hashref, the primary key is expected as
           the value for the '-pk' key, and the key '-parent' may be
           used to provide the primary key to the parent node instead
           of a second argument, and if present the key '-tree' can
           provide a new value (as primary key) for the tree of which
           this node is part.

=cut

sub update_node{
    my $self = shift;
    my ($nodeh, $parent) = @_;

    # unify the parent from the different ways it can be provided
    if (ref($parent)) {
        $parent = $parent->node_id();
    } elsif (!defined($parent)) {
        $parent = $nodeh->{'-parent'} if exists($nodeh->{'-parent'});
    }

    # unify the hashref and object options to a single format
    my $data = $self->_node_to_hash($nodeh);

    # store in database
    my $sth = $self->{'_sths'}->{'updateNode'};
    if (! $sth) {
        $sth = $self->_prepare(
            "UPDATE node SET "
            ."parent_id = IFNULL(?,parent_id), "
            ."label = IFNULL(?,label), "
            ."distance_to_parent = IFNULL(?,distance_to_parent), "
            ."annotations = IFNULL(?,annotations) "
            ."WHERE node_id = ?");
        $self->{'_sths'}->{'updateNode'} = $sth;
    }
    my $rv = $sth->execute($parent, 
                           $data->{'-id'}, $data->{'-branch_length'}, 
                           $data->{'-flatAnnotations'},
                           $data->{'-pk'});
    # done
    return $rv;
}

=head2 insert_tree

 Title   : insert_tree
 Usage   : $dbkey = $store->insert_tree($tree)
 Function: Inserts (adds) the given tree into the store.
 Example :
 Returns : If successful, the primary key to the newly created tree.

 Args :    The tree to be inserted, as a Bio::Tree::TreeI compliant
           object or a hashref.

=cut

sub insert_tree {
    my $self = shift;
    my $treeh = shift;
    my $annotations = join(";",map { sprintf("%s=%s",$_,
					   join(",",$treeh->get_tag_values($_))) } 
			 $treeh->get_all_tags);
  my $sth = $self->_prepare(<<END);
INSERT INTO node (tree_id,label,is_rooted,root_id,annotations) VALUES (?,?,?,?,?)
END
  $sth->execute(undef,$treeh->id,undef,$treeh->get_root_node,$annotations);
  $sth->finish;
}

sub _set_parent_ids {
  my $self = shift @_;
  my $parent_id = shift @_;
  my @nodes = @_;
  my $sth= $self->_prepare(<<END);
UPDATE node SET parent_id = ? WHERE node_id = ?
END

  for my $node ( @nodes ) {
    $sth->execute($parent_id,$node);
  }
  $sth->finish;
}

sub _fetch_node {
  my $self = shift;
  my $id   = shift;

#  my $sth = $self->_prepare(<<END);
#SELECT (node_id, parent_id, label, distance_to_parent,annotations) FROM node where node_id = ?
#END

  my $sth = $self->_prepare(<<END);
SELECT node_id FROM node where node_id = ?
END

  $sth->execute($id);
#  my ($nid,$pid,$lbl,$distance,$annot) = @{$sth->fetchrow_arrayref};
  my ($nid) = @{$sth->fetchrow_arrayref};
  return Bio::DB::Tree::Node->new(-node_id => $nid,
				  -store   => $self);
#				  -parent_id   => $pid,#
#				  -id          => $lbl#,
#				  -branch_lengths => $distance,
#				  -annotations => $annot,
#				  -store        => $self);
}

sub _fetch_node_children {
  my $self = shift;
  my $id   = shift;
  my $sortby = shift;

  my $sth = $self->_prepare(<<END);
SELECT node_id FROM node WHERE parent_id = ?
END
  $sth->execute($id);
  my @nodes;
  for my $nid ( @{$sth->fetchrow_arrayref}) {
    push @nodes, Bio::DB::Tree::Node->new(-node_id => $nid);
  }
  return @nodes;
}


sub _fetch_node_all_children {
  my $self = shift;
  my $id   = shift;
  my $sortby = shift;

  my $sth = $self->_prepare(<<END);
SELECT node_id FROM node WHERE left_idx <= ? AND right_idx >= ?
END
  $sth->execute($id);
  my @nodes;
  for my $nid ( @{$sth->fetchrow_arrayref}) {
    push @nodes, Bio::DB::Tree::Node->new(-node_id => $nid);
  }
  return @nodes;
}

sub _fetch_node_branch_length {
  my $self = shift;
  my $id   = shift;
  my $sth = $self->_prepare(<<END);
SELECT distance_to_parent FROM node WHERE node_id = ?
END
  $sth->execute($id);
  my ($d) = @{$sth->fetchrow_arrayref || []};
  $sth->finish;
  return $d;
}

sub _fetch_node_label {
  my $self = shift;
  my $id   = shift;
  my $sth = $self->_prepare(<<END);
SELECT label FROM node WHERE node_id = ?
END
  my $l = @{$sth->fetchrow_array};
  $sth->finish;
  return $l;
}

sub _fetch_node_parent_id {
  my $self = shift;
  my $id   = shift;
  # being lazy - just get the parent_id and then fetch_node from that ID
  my $sth = $self->_prepare(<<END);
SELECT parent_id FROM node WHERE node_id = ?
END
  $sth->execute($id);
  my ($pid) = @{$sth->fetchrow_arrayref};
  $sth->finish;
  $pid;
}
sub _fetch_node_parent {
  my $self = shift;
  $self->_fetch_node($self->_fetch_node_parent_id(shift));
}


sub _unset_node_parent {
  my $self = shift;
  my $id   = shift;
  my $sth = $self->_prepare(<<END);
UPDATE node set parent_id = NULL where node_id = ?
END
  $sth->execute($id);
  $sth->finish;
}

sub _delete_node {
  my $self = shift;
  my $id   = shift;

  my $sth = $self->_prepare(<<END);
DELETE FROM node self, node n WHERE n.left_idx >= s.left_idx AND n.right_idx <= s.right_idx AND n.node_id = ?
END
  $sth->execute($id);
  $sth->finish;
#  $self->dbh->commit;
}


sub _is_Leaf {
  my $self = shift;
  my $id = shift;
  my $sth = $self->_prepare(<<END);
SELECT COUNT(*) FROM node WHERE node_id = ? AND left_idx == right_idx
END
  my ($isleaf) = @{$sth->fetchrow_arrayref};
  return $isleaf;
}

=head2 Tree methods

=cut

sub _fetch_tree_root_node {
  my $self = shift;
  my $treeid = shift;

  my $sth = $self->_prepare(<<END);
SELECT root_id FROM tree WHERE tree_id = ?
END
  $sth->execute($treeid);
  my ($root_node) = @{$self->fetchrow_arrayref};
  $self->_fetch_node($root_node);
}

=head2 DB management methods

=cut

sub max_id {
  my $self = shift;
  my $type = shift;
  my $tbl;
  if ( $type =~ /node/i ) {
    $tbl = $self->_node_table;
  } elsif ( $type =~ /tree/i ) {
    $tbl = $self->_tree_table;
  } else {
    $self->throw("cannot call max id without a type");
  }

  my $sth  = $self->_prepare("SELECT max(id) from $tbl");
  $sth->execute or $self->throw($sth->errstr);
  my ($id) = $sth->fetchrow_array;
  $id;
}

sub _init_database {
  my $self  = shift;
  my $erase = shift;

  my $dbh    = $self->dbh;
  my $tables = $self->table_definitions;
  for my $t (keys %$tables) {
    $dbh->do("DROP table IF EXISTS $t") if $erase;
    my $query = "CREATE TABLE IF NOT EXISTS $t $tables->{$t}";
    $self->_create_table($dbh,$query);
  }
  1;
}


sub _create_table {
    my $self         = shift;
    my ($dbh,$query) = @_;
    for my $q (split ';',$query) {
	chomp($q);
	next unless $q =~ /\S/;
	$dbh->do("$q;\n") or $self->throw("$q -- ".$dbh->errstr);
    }
}

sub init_tmp_database {
  my $self = shift;

  my $dbh    = $self->dbh;
  my $tables = $self->table_definitions;

  for my $t (keys %$tables) {
    next if $t eq 'meta';  # done earlier
    my $table = $self->_qualify($t);
    my $query = "CREATE TEMPORARY TABLE $table $tables->{$t}";
    $self->_create_table($dbh,$query);
  }
  1;
}

sub _prepare {
  my $self = shift;
  $self->{dbh}->prepare(@_);
}

sub dbh {
  shift->{dbh}
}

sub optimize {
  my $self = shift;
  $self->dbh->do("VACUUM TABLE $_") foreach $self->index_tables;
}

sub index_tables {
  my $self = shift;
  return qw(node tree)
}

sub _enable_keys  { }  # nullop
sub _disable_keys { }  # nullop

##
# flatten out into a string the tag/value annotations of a Bio::AnnotatableI
##
sub _flatten_annotations {
    my $annHolder = shift;
    my @tags = $annHolder->get_all_tags;
    my $flatAnnot;
    if (@tags) {
        $flatAnnot = 
            join(";",
                 map { sprintf("%s=%s",$_,
                               join(",",$annHolder->get_tag_values($_)))
                 } 
                 @tags);
    }
    return $flatAnnot;
}

##
# flatten out into a string the key/value pairs of a hash
##
sub _flatten_keyvalues {
    my $h = shift;
    my $flatAnnot;
    if ($h && keys(%$h)) {
        $flatAnnot = join(";",
                          map { 
                              sprintf("%s=%s",$_,join(",",$h->{$_}))
                          } 
                          keys(%$h));
    }
    return $flatAnnot;
}

=head1 NAME

Bio::DB::Tree::Store::DBI::SQLite -

=head1 SYNOPSIS

  use Bio::DB::Tree::Store;

  # Open the tree database
  my $db = Bio::DB::Tree::Store->new(-adaptor => 'DBI::SQLite',
                                     -dsn     => '/path/to/database.db');

  my $id = 1;
  my $tree = $db->fetch($id);


=head1 DESCRIPTION

Bio::DB::Tree::Store::SQLite is the SQLite adaptor for
Bio::DB::Tree::Store. You will not create it directly, but
instead use Bio::DB::Tree::Store-E<gt>new() to do so.

See L<Bio::DB::Tree::Store> for complete usage instructions.

=head2 Using the SQLite adaptor

To establish a connection to the database, call
Bio::DB::Tree::Store-E<gt>new(-adaptor=E<gt>'DBI::SQLite',@more_args). The
additional arguments are as follows:


=head1 AUTHOR

Jason Stajich - jason-at-bioperl.org

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. See the BioPerl license for
more details.


=cut

1;
