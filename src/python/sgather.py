#!/usr/bin/env python
import utils,indmffile,sys,re,os
import optparse
from scipy import *

import numpy
nv = map(int,numpy.__version__.split('.'))
if (nv[0],nv[1]) < (1,6):
    loadtxt = io.read_array
    def savetxt(filename, data):
        io.write_array(filename, data, precision=16)  

def union(data):
    " Takes a union of array or list"
    c = []
    for d in data:
        if d not in c:
            c.append(d)
    return c

def SimplifySiginds(siginds):
    " Takes dictionary of Sigind's and creates list or non-zero columns"

    
    colsp={}
    colsm={}
    for icix in siginds.keys():
        Sigind = siginds[icix]
        cols_all = union(array(Sigind).flatten())
        cols_all = sorted(cols_all,key=lambda x: abs(x))
        colp=filter(lambda x: x>0, cols_all)
        colm=filter(lambda x: x<0, cols_all)
        #col = sort(union(array(Sigind).flatten())).tolist()
        #if 0 in col: col.remove(0)
        colsp[icix] = colp
        colsm[icix] = colm
    return (colsp,colsm)


if __name__=='__main__':
    """ Takes the self-energy files from all impurity problems, and combines
    them into a single self-energy file.
    """
    usage = """usage: %prog [ options ]

    The script takes the self-energy files from all impurity problems,
    and combines them into a single self-energy file.

    To give filename, you can use the following expressions:
      - word 'case', which will be replaced by current case, determined by
                    the presence of struct file.
      - '?', which will be replaced by icix.
    """

    parser = optparse.OptionParser(usage)
    parser.add_option("-o", "--osig", dest="osig", default='sig.inp', help="filename of the output self-energy file. Default: 'sig.inp'")
    parser.add_option("-i", "--isig", dest="isig", default='imp.?/sig.out', help="filename of the input self-energy from all impurity problems. Default: 'imp.?/sig.out'")
    parser.add_option("-l", "--lext", dest="m_extn", default='', help="For magnetic calculation, it can be 'dn'.")
    parser.add_option("-m", "--mix", dest="mix", type=float, default=1.0, help="Mixing parameter for self-energy. Default=1 -- no mixing")

    # Next, parse the arguments
    (options, args) = parser.parse_args()
    
    env = utils.W2kEnvironment()
    case = env.case
    
    options.osig = re.sub(r'case', case, options.osig)
    options.isig = re.sub(r'case', case, options.isig)
    
    print 'case=%s, isig=%s, osig=%s' %  (case, options.isig, options.osig)
    
    
    inl = indmffile.Indmfl(case)
    inl.read()
    if options.m_extn:
        inldn = indmffile.Indmfl(case, 'indmfl'+options.m_extn)
        inldn.read()
                         
    iSiginds = utils.ParsIndmfi(case)
    icols,icolsm = SimplifySiginds(iSiginds)
    print 'icols=', icols
    
    colsp,colsm = SimplifySiginds(inl.siginds)
    print 'colsp=', colsp, 'colsm=', colsm

    if options.m_extn:
        colspdn, colsmdn = SimplifySiginds(inldn.siginds)
        print 'colspdn=', colspdn, 'colsmdn=', colsmdn


    #allcols = array(icols.values()).flatten()
    allcols = sort( reduce(lambda x,y: x+y, icols.values()) )
    print 'allcols=', allcols
    print 'len(allcols)=', len(allcols)
    noccur = zeros(max(allcols),dtype=int)
    print 'len(noccur)=', len(noccur)

    missing_columns={}
    for icix in colsm.keys():
        for i in colsm[icix]: # missing columns do not appear in self-energy
            missing_columns[abs(i)]=1
    print 'missing_columns=', missing_columns

    for c in allcols:
        noccur[c-1]+=1
    print 'noccur=', noccur
    
    filename = re.sub(r'\?', str(0), options.isig)
    om = loadtxt(filename).transpose()[0]
    
    # Array of all sigmas
    rSigma=zeros(( len(allcols)*2+1, len(om) ),dtype=float)
    rs_oo=zeros( len(allcols)+len(missing_columns) ,dtype=float)
    rEdc=zeros( len(allcols)+len(missing_columns) ,dtype=float)
    rSigma[0] = om
    print 'shape(rSigma)', shape(rSigma)
    print 'shape(rs_oo)=', shape(rs_oo)

    # Reading self-energies from all impurity problems
    for icix in icols.keys():
        # Processing Delta
        #mincol = min(icols[icix])
        #maxcol = max(icols[icix])
        
        filename = re.sub(r'\?', str(icix), options.isig)
        print ('icix=%d reading from: %s' % (icix, filename)), 'cols=', icols[icix]
        
        # Searching for s_oo and Edc
        fh_sig = open(filename, 'r')
        exec(fh_sig.next()[1:].strip())
        exec(fh_sig.next()[1:].strip())
        fh_sig.close()
        # reading sigma
        #data = loadtxt(fh_sig).transpose()
        data = loadtxt(filename).transpose()
        fh_sig.close()
        
        for iic,c in enumerate(icols[icix]):
            imiss = len(filter(lambda x: x<=c, missing_columns))
            ic = c-imiss
            #print 'writting into ', 2*ic-1, 'and', 2*ic, 'from data at ', 2*(c-mincol+1)-1, 'and', 2*(c-mincol+1)
            print 'writting into ', 2*ic-1, 'and', 2*ic, 'from data at ', 2*iic+1, 'and', 2*iic+2
            #rSigma[2*ic-1] += data[2*(c-mincol+1)-1]*(1./noccur[c-1])
            #rSigma[2*ic]   += data[2*(c-mincol+1)  ]*(1./noccur[c-1])
            rSigma[2*ic-1] += data[2*iic+1]*(1./noccur[c-1])
            rSigma[2*ic]   += data[2*iic+2]*(1./noccur[c-1])
        
        for iic,c in enumerate(icols[icix]):
            #print 'writting s_oo into ', c-1, 'from', c-mincol
            print 'writting s_oo into ', c-1, 'from', iic
            rs_oo[c-1] += s_oo[iic]*(1./noccur[c-1])
            rEdc[c-1]  += Edc[iic]*(1./noccur[c-1])
        

    # The impurity self-energy has a static contribution
    # equal to s_oo-Edc
    # This self-energy will however go to zero in infinity. No static contribution
    for c in allcols: 
        imiss = len(filter(lambda x: x<=c, missing_columns))
        ic = c-imiss
        rSigma[2*ic-1] -= (rs_oo[c-1]-rEdc[c-1])


    cm = colsm.values()
    if options.m_extn:
        cm += colsmdn.values()
    cm=array(union(cm)).flatten()
    print 'cm=', cm

    if len(missing_columns)>0: # Some columns contain only s_oo and Edc (no dynamic component)
        # old-s_oo and old-Edc
        fi = open(options.osig,'r') # checking old s_oo and Edc from sig.inp
        exec(fi.next()[1:].strip())
        exec(fi.next()[1:].strip())
        fi.close()
        for i in missing_columns.keys():
            rs_oo[i-1] = s_oo[i-1]
            rEdc[i-1] = Edc[i-1]
            


    if options.mix!=1.0 and os.path.isfile(options.osig) and os.path.getsize(options.osig)>0:
        print 'Mixing self-energy with mix=', options.mix
        fi = open(options.osig,'r') # checking old s_oo and Edc
        exec(fi.next()[1:].strip())
        exec(fi.next()[1:].strip())
        fi.close()
        rSigma_old = loadtxt(options.osig).transpose()

        # The number of frequencies should be the same, but sometimes some frequencies are mising in the new iteration. Than mix just existing frequencies
        nom_new = shape(rSigma)[1]
        print 'shape sigma old', shape(rSigma_old)
        print 'shape sigma new', shape(rSigma)
        
        rs_oo[:] = options.mix*rs_oo[:]  + (1-options.mix)*array(s_oo)
        rEdc[:]  = options.mix*rEdc[:]   + (1-options.mix)*array(Edc)
        rSigma = options.mix*rSigma[:,:] + (1-options.mix)*rSigma_old[:,:nom_new]

    
    fout = open(options.osig, 'w')
    print >> fout, '# s_oo=', rs_oo.tolist()
    print >> fout, '# Edc=', rEdc.tolist()
    savetxt(fout,rSigma.transpose())
