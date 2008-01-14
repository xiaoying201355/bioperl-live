# $Id$
#
# BioPerl module for Bio::DB::EUtilities
#
# Cared for by Chris Fields <cjfields at uiuc dot edu>
#
# Copyright Chris Fields
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code
# 
# EUtil-based extension of GenericWebDBI interface 

=head1 NAME

Bio::DB::EUtilities - webagent which interacts with and retrieves data from
NCBI's eUtils

=head1 SYNOPSIS

...To be added!

=head1 DESCRIPTION

This is a general webagent which posts and retrieves data to NCBI's eUtilities
service using their CGI interface.  

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the 
evolution of this and other Bioperl modules. Send
your comments and suggestions preferably to one
of the Bioperl mailing lists. Your participation
is much appreciated.

  bioperl-l@lists.open-bio.org               - General discussion
  http://www.bioperl.org/wiki/Mailing_lists  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to
help us keep track the bugs and their resolution.
Bug reports can be submitted via the web.

  http://bugzilla.open-bio.org/

=head1 AUTHOR 

Email cjfields at uiuc dot edu

=head1 APPENDIX

The rest of the documentation details each of the
object methods. Internal methods are usually
preceded with a _

=cut

# Let the code begin...

package Bio::DB::EUtilities;
use strict;
use Bio::DB::EUtilParameters;
use Bio::Tools::EUtilities;

use base qw(Bio::DB::GenericWebAgent);

sub new {
    my($class,@args) = @_;
    my $self = $class->SUPER::new(@args);
    my $params = Bio::DB::EUtilParameters->new(-verbose => $self->verbose,
                                               @args);
    # cache parameters
    $self->parameter_base($params);
    return $self;
}

=head1 Bio::DB::GenericWebAgent methods

=head1 GenericWebDBI methods

=head2 parameter_base

 Title   : parameter_base
 Usage   : $dbi->parameter_base($pobj);
 Function: Get/Set Bio::ParameterBaseI.
 Returns : Bio::ParameterBaseI object
 Args    : Bio::ParameterBaseI object

=cut

=head2 ua

 Title   : ua
 Usage   : $dbi->ua;
 Function: Get/Set LWP::UserAgent.
 Returns : LWP::UserAgent
 Args    : LWP::UserAgent

=cut

=head2 get_Response

 Title   : get_Response
 Usage   : $agent->get_Response;
 Function: Get the HTTP::Response object by passing it an HTTP::Request (generated from
           Bio::ParameterBaseI implementation).
 Returns : HTTP::Response object or data if callback is used
 Args    : (optional)
 
           -cache_response - flag to cache HTTP::Response object; 
                             Default is 1 (TRUE, caching ON)
                             
           These are passed on to LWP::UserAgent::request() if stipulated
           
           -file   - use a LWP::UserAgent-compliant callback
           -cb     - dumps the response to a file (handy for large responses)
                     Note: can't use file and callback at the same time
           -read_size_hint - bytes of content to read in at a time to pass to callback
 Note    : Caching and parameter checking are set

=cut

=head2 delay

 Title   : delay
 Usage   : $secs = $self->delay([$secs])
 Function: get/set number of seconds to delay between fetches
 Returns : number of seconds to delay
 Args    : new value

NOTE: the default is to use the value specified by delay_policy().
This can be overridden by calling this method.

=cut

=head1 LWP::UserAgent related methods

=head2 proxy

 Title   : proxy
 Usage   : $httpproxy = $db->proxy('http')  or
           $db->proxy(['http','ftp'], 'http://myproxy' )
 Function: Get/Set a proxy for use of proxy
 Returns : a string indicating the proxy
 Args    : $protocol : an array ref of the protocol(s) to set/get
           $proxyurl : url of the proxy to use for the specified protocol
           $username : username (if proxy requires authentication)
           $password : password (if proxy requires authentication)

=cut

=head2 authentication

 Title   : authentication
 Usage   : $db->authentication($user,$pass)
 Function: Get/Set authentication credentials
 Returns : Array of user/pass
 Args    : Array or user/pass

=cut

=head2 delay_policy

  Title   : delay_policy
  Usage   : $secs = $self->delay_policy
  Function: return number of seconds to delay between calls to remote db
  Returns : number of seconds to delay
  Args    : none

  NOTE: NCBI requests a delay of 3 seconds between requests.  This method
        implements that policy.  This may change to check time of day for lengthening delays if needed

=cut

sub delay_policy {
  my $self = shift;
  return 3;
}

=head2 get_Parser

 Title   : get_Parser
 Usage   : $agent->get_Parser;
 Function: Retrieve the parser used for last agent request
 Returns : The Bio::Tools::EUtilities parser used to parse the HTTP::Response
           content
 Args    : None
 Note    : Abstract method; defined by implementation

=cut

sub get_Parser {
    my ($self) = @_;
    my $pobj = $self->parameter_base;
    if ($pobj->parameters_changed || !$self->{'_parser'}) {
        my $eutil = $pobj->eutil ;
        if ($eutil eq 'efetch') {
            $self->throw("No parser defined for efetch; use get_Response() directly");
        };
        # if we are to add pipe/tempfile support this would probably be the
        # place to add it....
        my $parser = Bio::Tools::EUtilities->new(
                            -eutil => $eutil,
                            -response => $self->get_Response,
                            -verbose => $self->verbose);
        return $self->{'_parser'} = $parser;
    }
    return $self->{'_parser'};
}

=head1 Bio::DB::EUtilParameters-delegating methods

This is only a subset of parameters available from Bio::DB::EUtilParameters (the
ones deemed absolutely necessary).  All others are available by calling
'parameter_base->method' when needed.

=cut

=head2 set_parameters

 Title   : set_parameters
 Usage   : $pobj->set_parameters(@params);
 Function: sets the NCBI parameters listed in the hash or array
 Returns : None
 Args    : [optional] hash or array of parameter/values.  
 Note    : This sets any parameter (i.e. doesn't screen them).  In addition to
           regular eutil-specific parameters, you can set the following:
           
           -eutil    - the eUtil to be used (default 'efetch')
           -history  - pass a HistoryI-implementing object, which
                       sets the WebEnv, query_key, and possibly db and linkname
                       (the latter two only for LinkSets)
           -correspondence - Boolean flag, set to TRUE or FALSE; indicates how
                       IDs are to be added together for elink request where
                       ID correspondence might be needed
                       (default 0)

=cut

sub set_parameters {
    my ($self, @args) = @_;
    # just ensures that parser instance isn't reused    
    delete $self->{'_parser'};
    $self->parameter_base->set_parameters(@args);
}

=head2 reset_parameters

 Title   : reset_parameters
 Usage   : resets values
 Function: resets parameters to either undef or value in passed hash
 Returns : none
 Args    : [optional] hash of parameter-value pairs
 Note    : this also resets eutil(), correspondence(), and the history and request
           cache

=cut

sub reset_parameters {
    my ($self, @args) = @_;
    # just ensures that parser instance isn't reused
    delete $self->{'_parser'};
    $self->parameter_base->reset_parameters(@args);
}

=head2 available_parameters

 Title   : available_parameters
 Usage   : @params = $pobj->available_parameters()
 Function: Returns a list of the available parameters
 Returns : Array of available parameters (no values)
 Args    : [optional] A string; either eutil name (for returning eutil-specific
           parameters) or 'history' (for those parameters allowed when retrieving
           data stored on the remote server using a 'Cookie').  

=cut

sub available_parameters {
    my ($self, @args) = @_;
    return $self->parameter_base->available_parameters(@args);
}

=head2 get_parameters

 Title   : get_parameters
 Usage   : @params = $pobj->get_parameters;
           %params = $pobj->get_parameters;
 Function: Returns list of key/value pairs, parameter => value
 Returns : Flattened list of key-value pairs. All key-value pairs returned,
           though subsets can be returned based on the '-type' parameter.  
           Data passed as an array ref are returned based on whether the
           '-join_id' flag is set (default is the same array ref). 
 Args    : -type : the eutil name or 'history', for returning a subset of
                parameters (Default: returns all)
           -join_ids : Boolean; join IDs based on correspondence (Default: no join)

=cut

sub get_parameters {
    my ($self, @args) = @_;
    return $self->parameter_base->available_parameters(@args);
}

=head1 Bio::Tools::EUtilities-delegating methods

=cut

=head1 Bio::Tools::EUtilities::EUtilDataI methods

=head2 eutil

 Title    : eutil
 Usage    : $eutil->$foo->eutil
 Function : Get/Set eutil
 Returns  : string
 Args     : string (eutil)
 Throws   : on invalid eutil
 
=cut

sub eutil {
    my ($self, @args) = @_;
    return $self->get_Parser->eutil(@args);
}

=head2 datatype

 Title    : datatype
 Usage    : $type = $foo->datatype;
 Function : Get/Set data object type
 Returns  : string
 Args     : string

=cut

sub datatype {
    my ($self, @args) = @_;
    return $self->get_Parser->datatype(@args);
}

=head1 Methods useful for multiple eutils

=head2 get_ids

 Title    : get_ids
 Usage    : my @ids = $parser->get_ids
 Function : returns array or array ref of requestes IDs
 Returns  : array or array ref (based on wantarray)
 Args     : [conditional] not required except when running elink queries against
            multiple databases. In case of the latter, the database name is
            optional (but recommended) when retrieving IDs as the ID list will
            be globbed together. If a db name isn't provided a warning is issued
            as a reminder.

=cut

sub get_ids {
    my ($self, @args) = @_;
    return $self->get_Parser->get_ids(@args);
}

=head2 get_database

 Title    : get_database
 Usage    : my $db = $info->get_database;
 Function : returns database name (eutil-compatible)
 Returns  : string
 Args     : none
 Note     : implemented for einfo and espell
 
=cut

sub get_database {
    my ($self, @args) = @_;
    return $self->get_Parser->get_database(@args);
}

=head2 get_db (alias for get_database)

=cut

sub get_db {
    my ($self, @args) = @_;
    return $self->get_Parser->get_db(@args);
}

=head2 next_History

 Title    : next_History
 Usage    : while (my $hist=$parser->next_History) {...}
 Function : returns next HistoryI (if present).
 Returns  : Bio::Tools::EUtilities::HistoryI (Cookie or LinkSet)
 Args     : none
 Note     : next_cookie() is an alias for this method. esearch, epost, and elink
            are all capable of returning data which indicates search results (in
            the form of UIDs) is stored on the remote server. Access to this
            data is wrapped up in simple interface (HistoryI), which is
            implemented in two classes: Bio::DB::EUtilities::Cookie (the
            simplest) and Bio::DB::EUtilities::LinkSet. In general, calls to
            epost and esearch will only return a single HistoryI object (a
            Cookie), but calls to elink can generate many depending on the
            number of IDs, the correspondence, etc.  Hence this iterator, which
            allows one to retrieve said data one piece at a time.

=cut

sub next_History {
    my ($self, @args) = @_;
    return $self->get_Parser->next_History(@args);
}

=head2 get_Histories

 Title    : get_Histories
 Usage    : my @hists = $parser->get_Histories
 Function : returns list of HistoryI objects.
 Returns  : list of Bio::Tools::EUtilities::HistoryI (Cookie or LinkSet)
 Args     : none

=cut

sub get_Histories {
    my ($self, @args) = @_;
    return $self->get_Parser->get_Histories(@args);
}

=head1 Query-related methods

=head2 get_count

 Title    : get_count
 Usage    : my $ct = $parser->get_count
 Function : returns the count (hits for a search)
 Returns  : integer
 Args     : [CONDITIONAL] string with database name - used to retrieve
            count from specific database when using egquery

=cut

sub get_count {
    my ($self, @args) = @_;
    return $self->get_Parser->get_count(@args);
}
=head2 get_queried_databases

 Title    : get_queried_databases
 Usage    : my @dbs = $parser->get_queried_databases
 Function : returns list of databases searched with global query
 Returns  : array of strings
 Args     : none
 Note     : predominately used for egquery; if used with other eutils will
            return a list with the single database

=cut

sub get_queried_databases {
    my ($self, @args) = @_;
    return $self->get_Parser->get_queried_databases(@args);
}
=head2 get_term

 Title   : get_term
 Usage   : $st = $qd->get_term;
 Function: retrieve the term for the global search
 Returns : string
 Args    : none

=cut

# egquery and espell

sub get_term {
    my ($self, @args) = @_;
    return $self->get_Parser->get_term(@args);
}
=head2 get_translation_from

 Title   : get_translation_from
 Usage   : $string = $qd->get_translation_from();
 Function: portion of the original query replaced with translated_to()
 Returns : string
 Args    : none

=cut

# esearch

sub get_translation_from {
    my ($self, @args) = @_;
    return $self->get_Parser->get_translation_from(@args);
}

=head2 get_translation_to

 Title   : get_translation_to
 Usage   : $string = $qd->get_translation_to();
 Function: replaced string used in place of the original query term in translation_from()
 Returns : string
 Args    : none

=cut

sub get_translation_to {
    my ($self, @args) = @_;
    return $self->get_Parser->get_translation_to(@args);
}

=head2 get_retstart

 Title   : get_retstart
 Usage   : $start = $qd->get_retstart();
 Function: retstart setting for the query (either set or NCBI default)
 Returns : Integer
 Args    : none

=cut

sub get_retstart {
    my ($self, @args) = @_;
    return $self->get_Parser->get_retstart(@args);
}

=head2 get_retmax

 Title   : get_retmax
 Usage   : $max = $qd->get_retmax();
 Function: retmax setting for the query (either set or NCBI default)
 Returns : Integer
 Args    : none

=cut

sub get_retmax {
    my ($self, @args) = @_;
    return $self->get_Parser->get_retmax(@args);
}

=head2 get_query_translation

 Title   : get_query_translation
 Usage   : $string = $qd->get_query_translation();
 Function: returns the translated query used for the search (if any)
 Returns : string
 Args    : none
 Note    : this differs from the original term.

=cut

sub get_query_translation {
    my ($self, @args) = @_;
    return $self->get_Parser->get_query_translation(@args);
}

=head2 get_corrected_query

 Title    : get_corrected_query
 Usage    : my $cor = $eutil->get_corrected_query;
 Function : retrieves the corrected query when using espell
 Returns  : string 
 Args     : none

=cut

sub get_corrected_query {
    my ($self, @args) = @_;
    return $self->get_Parser->get_corrected_query(@args);
}

=head2 get_replaced_terms

 Title    : get_replaced_terms
 Usage    : my $term = $eutil->get_replaced_term
 Function : returns array of strings replaced in the query
 Returns  : string 
 Args     : none

=cut

sub get_replaced_terms {
    my ($self, @args) = @_;
    return $self->get_Parser->get_replaced_terms(@args);
}

=head2 next_GlobalQuery

 Title    : next_GlobalQuery
 Usage    : while (my $query = $eutil->next_GlobalQuery) {...}
 Function : iterates through the queries returned from an egquery search
 Returns  : GlobalQuery object
 Args     : none

=cut

sub next_GlobalQuery {
    my ($self, @args) = @_;
    return $self->get_Parser->next_GlobalQuery(@args);
}

=head2 get_GlobalQueries

 Title    : get_GlobalQueries
 Usage    : @queries = $eutil->get_GlobalQueries
 Function : returns list of GlobalQuery objects
 Returns  : array of GlobalQuery objects
 Args     : none

=cut

sub get_GlobalQueries {
    my ($self, @args) = @_;
    return $self->get_Parser->get_GlobalQueries(@args);
}

=head1 Summary-related methods

=head2 next_DocSum

 Title    : next_DocSum
 Usage    : while (my $ds = $esum->next_DocSum) {...}
 Function : iterate through DocSum instances
 Returns  : single Bio::Tools::EUtilities::Summary::DocSum
 Args     : none yet

=cut

sub next_DocSum {
    my ($self, @args) = @_;
    return $self->get_Parser->next_DocSum(@args);
}

=head2 get_DocSums

 Title    : get_DocSums
 Usage    : my @docsums = $esum->get_DocSums
 Function : retrieve a list of DocSum instances
 Returns  : array of Bio::Tools::EUtilities::Summary::DocSum
 Args     : none

=cut

sub get_DocSums {
    my ($self, @args) = @_;
    return $self->get_Parser->get_DocSums(@args);
}

=head2 print_DocSums

 Title    : print_docsums
 Usage    : $docsum->print_docsums();
            $docsum->print_docsums(-fh => $fh, -callback => $coderef);
 Function : prints item data for all docsums.  The default printing method is
            each item per DocSum is printed with relevant values if present
            in a simple table using Text::Wrap.  
 Returns  : none
 Args     : [optional]
           -file : file to print to
           -fh   : filehandle to print to (cannot be used concurrently with file)
           -cb   : coderef to use in place of default print method.  This is passed
                   in a DocSum object; 
 Note     : if -file or -fh are not defined, prints to STDOUT

=cut

sub print_DocSums {
    my ($self, @args) = @_;
    return $self->get_Parser->print_DocSums(@args);
}

=head1 Info-related methods

=head2 get_available_databases

 Title    : get_available_databases
 Usage    : my @dbs = $info->get_available_databases
 Function : returns list of available eutil-compatible database names
 Returns  : Array of strings 
 Args     : none

=cut

sub get_available_databases {
    my ($self, @args) = @_;
    return $self->get_Parser->get_available_databases(@args);
}

=head2 get_record_count

 Title    : get_record_count
 Usage    : my $ct = $eutil->get_record_count;
 Function : returns database record count
 Returns  : integer
 Args     : none

=cut

sub get_record_count {
    my ($self, @args) = @_;
    return $self->get_Parser->get_record_count(@args);
}

=head2 get_last_update

 Title    : get_last_update
 Usage    : my $time = $info->get_last_update;
 Function : returns string containing time/date stamp for last database update
 Returns  : integer
 Args     : none

=cut

sub get_last_update {
    my ($self, @args) = @_;
    return $self->get_Parser->get_last_update(@args);
} 
=head2 get_menu_name

 Title    : get_menu_name
 Usage    : my $nm = $info->get_menu_name;
 Function : returns string of database menu name
 Returns  : string
 Args     : none
 
=cut

sub get_menu_name {
    my ($self, @args) = @_;
    return $self->get_Parser->get_menu_name(@args);
}

=head2 get_description

 Title    : get_description
 Usage    : my $desc = $info->get_description;
 Function : returns database description
 Returns  : string
 Args     : none

=cut

sub get_description {
    my ($self, @args) = @_;
    return $self->get_Parser->get_description(@args);
}

=head2 next_FieldInfo

 Title    : next_FieldInfo
 Usage    : while (my $field = $info->next_FieldInfo) {...}
 Function : iterate through FieldInfo objects
 Returns  : Field object
 Args     : none
 Note     : uses callback() for filtering if defined for 'fields'
 
=cut

sub next_FieldInfo {
    my ($self, @args) = @_;
    return $self->get_Parser->next_FieldInfo(@args);
}

=head2 get_FieldInfo

 Title    : get_FieldInfo
 Usage    : my @fields = $info->get_FieldInfo;
 Function : returns list of FieldInfo objects
 Returns  : array (FieldInfo objects)
 Args     : none

=cut

sub get_FieldInfo {
    my ($self, @args) = @_;
    return $self->get_Parser->get_FieldInfo(@args);
}

*get_FieldInfos = \&get_FieldInfo;

=head2 next_LinkInfo

 Title    : next_LinkInfo
 Usage    : while (my $link = $info->next_LinkInfo) {...}
 Function : iterate through LinkInfo objects
 Returns  : LinkInfo object
 Args     : none
 
=cut

sub next_LinkInfo {
    my ($self, @args) = @_;
    return $self->get_Parser->next_LinkInfo(@args);
}

=head2 get_LinkInfo

 Title    : get_LinkInfo
 Usage    : my @links = $info->get_LinkInfo;
 Function : returns list of LinkInfo objects
 Returns  : array (LinkInfo objects)
 Args     : none

=cut

sub get_LinkInfo {
    my ($self, @args) = @_;
    return $self->get_Parser->get_LinkInfo(@args);
}

*get_LinkInfos = \&get_LinkInfo;

=head1 Bio::Tools::EUtilities::Link-related methods

=head2 next_LinkSet

 Title    : next_LinkSet
 Usage    : while (my $ls = $eutil->next_LinkSet {...}
 Function : iterate through LinkSet objects
 Returns  : LinkSet objects
 Args     : none

=cut

sub next_LinkSet {
    my ($self, @args) = @_;
    return $self->get_Parser->next_LinkSet(@args);
}

=head2 get_LinkSets

 Title    : get_LinkSets
 Usage    : my @ls = $info->get_LinkSets;
 Function : returns list of LinkSet objects
 Returns  : array (LinkSet objects)
 Args     : none

=cut

# add support for retrieval of data if lazy parsing is enacted

sub get_LinkSets {
    my ($self, @args) = @_;
    return $self->get_Parser->get_LinkSets(@args);
}

=head2 get_linked_databases

 Title    : get_linked_databases
 Usage    : my @dbs = $eutil->get_linked_databases
 Function : returns list of databases linked to in linksets
 Returns  : array of databases
 Args     : none

=cut

sub get_linked_databases {
    my ($self, @args) = @_;
    return $self->get_Parser->get_linked_databases(@args);
}

=head1 Iterator- and callback-related methods

=cut

=head2 rewind

 Title    : rewind
 Usage    : $esum->rewind()
            $esum->rewind('recursive')
 Function : retrieve a list of DocSum instances
 Returns  : array of Bio::Tools::EUtilities::Summary::DocSum
 Args     : [optional] Scalar; string ('all') to reset all iterators, or string 
            describing the specific main object iterator to reset. The following
            are recognized (case-insensitive):
            
            'all' - rewind all objects and also recursively resets nested object
                    interators (such as LinkSets and DocSums).
            'globalqueries'
            'fieldinfo' or 'fieldinfos'
            'linkinfo' or 'linkinfos'
            'linksets'
            'docsums'

=cut

sub rewind {
    my ($self, $string) = @_;
    return $self->get_Parser->rewind($string);
}

=head2 generate_iterator

 Title    : generate_iterator
 Usage    : my $coderef = $esum->generate_iterator('linkinfo')
 Function : generates an iterator (code reference) which iterates through
            the relevant object indicated by the args
 Returns  : code reference
 Args     : [REQUIRED] Scalar; string describing the specific object to iterate.
            The following are currently recognized (case-insensitive):
            
            'globalqueries'
            'fieldinfo' or 'fieldinfos'
            'linkinfo' or 'linkinfos'
            'linksets'
            'docsums'
            
            A second argument can also be passed to generate a 'lazy' iterator,
            which loops through and returns objects as they are created (instead
            of creating all data instances up front, then iterating through,
            which is the default). Use of these iterators precludes use of
            rewind() for the time being as we can't guarantee you can rewind(),
            as this depends on whether the data source is seek()able and thus
            'rewindable'. We will add rewind() support at a later time which
            will work for 'seekable' data.
            
            A callback specified using callback() will be used to filter objects
            for any generated iterator. This behaviour is implemented for both
            normal and lazy iterator types and is the default. If you don't want
            this, make sure to reset any previously set callbacks via
            reset_callback() (which just deletes the code ref).
 TODO     : generate seekable iterators ala HOP for seekable fh data

=cut

sub generate_iterator {
    my ($self, @args) = @_;
    return $self->get_Parser->generate_iterator(@args);
}

=head2 callback

 Title    : callback
 Usage    : $parser->callback(sub {$_[0]->get_database eq 'protein'});
 Function : Get/set callback code ref used to filter returned data objects
 Returns  : code ref if previously set
 Args     : single argument:
            code ref - evaluates a passed object and returns true or false value
                       (used in iterators)
            'reset' - string, resets the iterator.
            returns upon any other args
=cut

sub callback {
    my ($self, @args) = @_;
    return $self->get_Parser->callback(@args);
}

1;
__END__