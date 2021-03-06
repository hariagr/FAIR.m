%==============================================================================
% This code is part of the Finite Element Method app for the Matlab-based toolbox
%  FAIR - Flexible Algorithms for Image Registration. 
% For details see 
% - https://github.com/C4IR/FAIRFEM 
%==============================================================================
%
% function [Sc,dS,d2S] = hyperElasticFEM(uc,yRef,Mesh,varargin)
%
% hyperelastic regularization based on tetrahedral finite element
% discretization with linear basis functions
%
% S(u)=\int a1*||\nabla u||^2 + a2*phi(cof\nabla(x+u)) + a3*psi(det\nabla(x+u))
%
% Input:
%   uc     - coefficients for displacement
%   yRef   - coefficients of reference transformation
%   Mesh   - description of mesh, struct
%
% ADDITIONALLY: we require the reference grid yRef,
%               use regularizer(...,'yRef',yRef)
%
% Output:
%    Sc    - hyperelastic energy
%    dS    - first derivative
%    d2S   - approximated Hessian
%
% see also hyperElastic.m
%==============================================================================

function [Sc,dS,d2S] = hyperElasticFEM(uc,yRef,Mesh,varargin)

persistent A  alphaLengthOld
if ~exist('A','var'),        A        = []; end;
if ~exist('omegaOld','var'), omegaOld = []; end;
if ~exist('mOld','var'),     mOld = []; end;
if nargin == 0, help(mfilename); runMinimalExample; return; end;

dS = []; d2S = [];

alpha       = regularizer('get','alpha');
if isempty(alpha), alpha=1; end
alphaLength = regularizer('get','alphaLength');
if isempty(alphaLength), alphaLength=1; end
alphaArea   = regularizer('get','alphaArea');
if isempty(alphaArea), alphaArea=1;     end
alphaVolume = regularizer('get','alphaVolume');
if isempty(alphaVolume), alphaVolume=1; end;
matrixFree  = 0;

doDerivative =( nargout>1);

for k=1:2:length(varargin), % overwrites default parameter
    eval([varargin{k},'=varargin{',int2str(k+1),'};']);
end;

alphaLength= alpha*alphaLength;
alphaVolume= alpha*alphaVolume;

yc = yRef + uc;
dim = Mesh.dim;
vol = Mesh.vol;

if not(matrixFree), % matrix-based
    % =====================================================================
    % length regularization
    build = isempty(alphaLengthOld) || any(alphaLengthOld~=alphaLength) ||...
        isempty(A) || size(A,2)~=numel(uc);
    if build,
        alphaLengthOld = alphaLength;
        A = alphaLength * (Mesh.B'*sdiag(repmat(vol,[dim^2,1]))*Mesh.B);
    end
    dSlength  = uc'*A;
    Slength  = 0.5*dSlength*uc;
    d2Slength = A;
    
    GRAD = Mesh.GRAD;
    By = reshape(GRAD*reshape(yc,[],dim),[],dim^2);
    % =====================================================================
    % area regularization
    if dim==3,
        [cof, dCof] = cofactor3D(By,Mesh,doDerivative,matrixFree);
        % compute areas
        area = [
            sum(cof(:,[1 4 7]).^2,2);
            sum(cof(:,[2 5 8]).^2,2);
            sum(cof(:,[3 6 9]).^2,2);
            ];
        % compute penalty
        [H,dH,d2H] = phiDW(area,doDerivative);
        % compute area regularizer
        Sarea   = alphaArea * repmat(vol,[3 1])'*H;
        
        % derivative of area regularizer
        if doDerivative,
            dSarea = zeros(1,numel(yc));
            d2Sarea = sparse(numel(yc),numel(yc));
            dH = sdiag(vol)*reshape(dH,[],3); 
            d2H = reshape(d2H,[],3);
            for i=1:3,
               dA = 2*(sdiag(cof(:,i))*dCof{i}+sdiag(cof(:,i+3))*dCof{i+3}+sdiag(cof(:,i+6))*dCof{i+6});
               dSarea  = dSarea +   alphaArea*(dH(:,i)'*dA);
               d2Sarea = d2Sarea + dA'*sdiag(alphaArea*vol.*d2H(:,i))*dA;
            end
            clear dA dH d2H
        end
        
    else
        Sarea = 0;
        dSarea = 0;
        d2Sarea = 0;
    end
    
    % =====================================================================
    % volume regularization
    if dim==2,
        D1 = Mesh.dx1; D2 = Mesh.dx2;
        det = By(:,1).*By(:,4) - By(:,3) .* By(:,2);
        if doDerivative,
            dDet = [sdiag(By(:,4))*D1 + sdiag(-By(:,3))*D2, ...
                    sdiag(-By(:,2))*D1+ sdiag(By(:,1))*D2];
        end
    else
        D1 = Mesh.dx1; D2 = Mesh.dx2; D3 = Mesh.dx3;
        % built via cofactor (save some time)
        det = By(:,1).*cof(:,1)+By(:,2).*cof(:,2)+By(:,3).*cof(:,3);
       
        if doDerivative,
            %Z = sparse(size(D1,1),size(D1,2));
            % simple product rule
            %dDet = [sdiag(cof(:,1))*D1 + sdiag(cof(:,2))*D2 + sdiag(cof(:,3))*D3,Z,Z]...
            %    + sdiag(By(:,1))*dCof{1} + sdiag(By(:,2))*dCof{2} + sdiag(By(:,3))*dCof{3};

            dDet = [sdiag(cof(:,1))*D1 + sdiag(cof(:,2))*D2 + sdiag(cof(:,3))*D3,...
                    sdiag(cof(:,4))*D1 + sdiag(cof(:,5))*D2 + sdiag(cof(:,6))*D3,...
                    sdiag(cof(:,7))*D1 + sdiag(cof(:,8))*D2 + sdiag(cof(:,9))*D3];

        end
    end
    [G,dG,d2G] = psi(det,doDerivative);
    Svolume   = alphaVolume *(vol'*G);
    Sc = Slength +Sarea + Svolume;

    if doDerivative
        % derivative of volume
        dSvolume  = alphaVolume * ((vol.*dG)'* dDet);
        d2Svolume = alphaVolume * (dDet' * (sdiag(vol.*d2G)) * dDet);
        if dim==3
            dS  = dSlength  + dSarea + dSvolume;
            d2S = d2Slength + d2Sarea + d2Svolume;
        elseif dim==2
            dS = dSlength + dSvolume;
            d2S = d2Slength + d2Svolume;
        end
    end
    
else % matrix-free
    d2S.regularizer = regularizer;
    d2S.alpha       = alpha;
    d2S.yc          = yc;
    d2S.solver      = 'PCG-hyperElastic';%@FEMMultiGridSolveHyper;
    
    % code only diffusion part for B
    d2S.By     = @(u,Mesh) Mesh.mfGRAD.D(u);
    d2S.BTy    = @(u,Mesh) Mesh.mfGRAD.Dadj(u);
    d2S.B      = @(Mesh)   Mesh.GRAD;
    
    % give seperate handles for diagonals of length, area and volume
    d2S.diagLength   = @(Mesh) getDiagLength(Mesh,alphaLength);
    d2S.diagArea     = @(Mesh) getDiagArea(Mesh,yc,alphaArea);
    d2S.diagVol      = @(Mesh) getDiagVolume(Mesh,yc,alphaVolume);
    
    % length regularizer
    dSlength = transpose( alphaLength* d2S.BTy(repmat(Mesh.vol,[dim^2,1]).*d2S.By(uc,Mesh),Mesh) );
    Slength  = .5*dSlength*uc;
    
    if doDerivative
        d2Slength = @(uc) alphaLength * d2S.BTy(repmat(Mesh.vol,[dim^2,1]).*d2S.By(uc,Mesh),Mesh);
    end
    
    % area regularizer
    if dim==3
        yc = reshape(yc,[],dim);
        [cof, dCof] = cofactor3D([],Mesh,doDerivative,matrixFree);
        % compute areas
        area = [
                cof{1}(yc).^2+cof{4}(yc).^2+cof{7}(yc).^2;
                cof{2}(yc).^2+cof{5}(yc).^2+cof{8}(yc).^2;
                cof{3}(yc).^2+cof{6}(yc).^2+cof{9}(yc).^2;
                ];    
        % compute penalty
        [H,dH,d2H] = phiDW(area,doDerivative);
        % compute area regularizer
        Sarea   = alphaArea * repmat(vol,[3 1])'*H;
        
        if doDerivative
            dH = reshape(dH,[],3);
            d2H = reshape(d2H,[],3);
            dAadj = @(x,i) 2*(dCof.dCofadj{i}(x.*cof{i}(yc),yc) + dCof.dCofadj{i+3}(x.*cof{i+3}(yc),yc) + dCof.dCofadj{i+6}(x.*cof{i+6}(yc),yc));
            dSarea = zeros(1,Mesh.nnodes*dim);
            for i=1:3          
               dSarea  = dSarea +   alphaArea*dAadj(vol.*dH(:,i),i)';
            end
            
            dA = @(x,i) 2*(cof{i}(yc).*dCof.dCof{i}(x,yc) + cof{i+3}(yc).*dCof.dCof{i+3}(x,yc) + cof{i+6}(yc).*dCof.dCof{i+6}(x,yc));
            d2Sarea = @(x) dAadj(alphaArea*vol.*d2H(:,1).*dA(reshape(x,[],3),1),1) + dAadj(alphaArea*vol.*d2H(:,2).*dA(reshape(x,[],3),2),2) + dAadj(alphaArea*vol.*d2H(:,3).*dA(reshape(x,[],3),3),3);
            
        end
        
    else
        Sarea = 0;
        dSarea = 0;
        d2Sarea = 0;
    end
    
    % volume regularizer
    if dim==2
        % volume term
        dx1 = Mesh.mfdx1; dx2 = Mesh.mfdx2;
        yc = reshape(yc,[],2);
        By = [dx1.D(yc(:,1))  dx2.D(yc(:,1)) dx1.D(yc(:,2)) dx2.D(yc(:,2))];
        det = By(:,1).*By(:,4) - By(:,3) .* By(:,2);
        [G,dG,d2G] = psi(det,doDerivative);
        Svolume = alphaVolume*sum(Mesh.vol.*G);
    
        if doDerivative
            
            dDet  = @(x)   By(:,4).*dx1.D(x(:,1))- By(:,3).*dx2.D(x(:,1))...
                                -By(:,2).*dx1.D(x(:,2))+By(:,1).*dx2.D(x(:,2));

            dDetadj = @(x) [ ...
                             dx1.Dadj(By(:,4).*x)-dx2.Dadj(By(:,3).*x);...
                            -dx1.Dadj(By(:,2).*x)+dx2.Dadj(By(:,1).*x)]; 
                        
            dSvolume = alphaVolume * transpose(dDetadj(dG.*Mesh.vol));
            
            d2Svolume = @(x) dDetadj(vol.*d2G.*dDet(reshape(x,[],2)));
            
        end
        
    else
        dx1 = Mesh.mfdx1; dx2 = Mesh.mfdx2; dx3 = Mesh.mfdx3;
        det = dx1.D(yc(:,1)).*cof{1}(yc) + dx2.D(yc(:,1)).*cof{2}(yc) + dx3.D(yc(:,1)).*cof{3}(yc);
        [G,dG,d2G] = psi(det,doDerivative);
        Svolume = alphaVolume*sum(Mesh.vol.*G);
        
        if doDerivative
            
            dDet = @(x)  cof{1}(yc).*dx1.D(x(:,1)) + cof{2}(yc).*dx2.D(x(:,1)) + cof{3}(yc).*dx3.D(x(:,1)) +...
                         cof{4}(yc).*dx1.D(x(:,2)) + cof{5}(yc).*dx2.D(x(:,2)) + cof{6}(yc).*dx3.D(x(:,2)) +...
                         cof{7}(yc).*dx1.D(x(:,3)) + cof{8}(yc).*dx2.D(x(:,3)) + cof{9}(yc).*dx3.D(x(:,3));
                              
            dDetadj = @(x) [ ...
                                 dx1.Dadj(cof{1}(yc).*x) + dx2.Dadj(cof{2}(yc).*x) + dx3.Dadj(cof{3}(yc).*x);...
                                 dx1.Dadj(cof{4}(yc).*x) + dx2.Dadj(cof{5}(yc).*x) + dx3.Dadj(cof{6}(yc).*x);...
                                 dx1.Dadj(cof{7}(yc).*x) + dx2.Dadj(cof{8}(yc).*x) + dx3.Dadj(cof{9}(yc).*x)
                                 ]; 
            
            dSvolume = alphaVolume * transpose(dDetadj(dG.*Mesh.vol));
            
            d2Svolume = @(x) alphaVolume * dDetadj(vol.*d2G.*dDet(reshape(x,[],3)));
            
        end
        
    end  
    Sc = Slength +Sarea + Svolume;
    
    if doDerivative
        if dim==3
            dS  = dSlength  + dSarea + dSvolume;
            d2S.d2S = @(x) d2Slength(x)  + d2Sarea(x) + d2Svolume(x);
            d2S.diag = @(yc) d2S.diagLength(Mesh) + d2S.diagArea(Mesh) + d2S.diagVol(Mesh);
        elseif dim==2
            dS = dSlength + dSvolume;
            d2S.d2S  = @(x) d2Slength(x) + d2Svolume(x);
            d2S.diag = @(yc) d2S.diagLength(Mesh) + d2S.diagVol(Mesh);
        end
    end
    
    
end


function D = getDiagVolume(Mesh,yc,alphaVolume)
dim = Mesh.dim;
vol = Mesh.vol;
if dim==2
    
    dphi  = Mesh.dphi;    
    dphi1 = dphi{1}; dphi2 = dphi{2}; dphi3 = dphi{3};
    
    % compute diagonal of volume regularizer
    % MB : dDet = [sdiag(By(:,4)), sdiag(-By(:,3)) , sdiag(-By(:,2)), sdiag(By(:,1))] * B;
    [dx1, dx2] = getGradientMatrixFEM(Mesh,1);
    yc = reshape(yc,[],2);
    By = [dx1.D(yc(:,1))  dx2.D(yc(:,1)) dx1.D(yc(:,2)) dx2.D(yc(:,2))];
    det = By(:,1).*By(:,4) - By(:,3) .* By(:,2);
    [~,~,d2G] = psi(det,1);
    
    % get boundaries
    Dxi = @(i,j) Mesh.mfPi(vol.*d2G.*(By(:,j).*dphi1(:,i)).^2,1) ... 
        + Mesh.mfPi(vol.*d2G.*(By(:,j).*dphi2(:,i)).^2,2) ...
        + Mesh.mfPi(vol.*d2G.*(By(:,j).*dphi3(:,i)).^2,3); % diagonal of Dxi'*Dxi 
    
    Dxy = @(i,j,k,l) Mesh.mfPi(vol.*d2G.*(By(:,j).*dphi1(:,i)).*(By(:,l).*dphi1(:,k)),1) ... % byproduct terms for verifications
        + Mesh.mfPi(vol.*d2G.*(By(:,j).*dphi2(:,i)).*(By(:,l).*dphi2(:,k)),2) ...
        + Mesh.mfPi(vol.*d2G.*(By(:,j).*dphi3(:,i)).*(By(:,l).*dphi3(:,k)),3); % diagonal of Dxi'*Dxi 
    
    D = [Dxi(1,4)+ Dxi(2,3) - 2*Dxy(1,4,2,3) ;Dxi(1,2)+ Dxi(2,1) - 2*Dxy(1,2,2,1)];

else
    dphi  = Mesh.dphi;   
    dphi1 = dphi{1}; dphi2 = dphi{2}; dphi3 = dphi{3}; dphi4 = dphi{4};
    
    [cof, dCof] = cofactor3D([],Mesh,0,1);
    yc = reshape(yc,[],3);
    dx1 = Mesh.mfdx1; dx2 = Mesh.mfdx2; dx3 = Mesh.mfdx3;
    det = dx1.D(yc(:,1)).*cof{1}(yc) + dx2.D(yc(:,1)).*cof{2}(yc) + dx3.D(yc(:,1)).*cof{3}(yc);
    [~,~,d2G] = psi(det,1);
    
    % get boundaries
    Dxi = @(i,j) Mesh.mfPi(vol.*d2G.*(cof{j}(yc).*dphi1(:,i)).^2,1) ... 
        + Mesh.mfPi(vol.*d2G.*(cof{j}(yc).*dphi2(:,i)).^2,2) ...
        + Mesh.mfPi(vol.*d2G.*(cof{j}(yc).*dphi3(:,i)).^2,3) ...
        + Mesh.mfPi(vol.*d2G.*(cof{j}(yc).*dphi4(:,i)).^2,4); % diagonal of Dxi'*Dxi 
    
    Dxy = @(i,j,k,l) Mesh.mfPi(vol.*d2G.*(cof{j}(yc).*dphi1(:,i)).*(cof{l}(yc).*dphi1(:,k)),1) ... % byproduct terms for verifications
        + Mesh.mfPi(vol.*d2G.*(cof{j}(yc).*dphi2(:,i)).*(cof{l}(yc).*dphi2(:,k)),2) ...
        + Mesh.mfPi(vol.*d2G.*(cof{j}(yc).*dphi3(:,i)).*(cof{l}(yc).*dphi3(:,k)),3) ...
        + Mesh.mfPi(vol.*d2G.*(cof{j}(yc).*dphi4(:,i)).*(cof{l}(yc).*dphi4(:,k)),4); % diagonal of Dxi'*Dxi 
    
    D1 = Dxi(1,1)+ Dxi(2,2) + Dxi(3,3) + 2*Dxy(1,1,2,2) + 2*Dxy(1,1,3,3) + 2*Dxy(2,2,3,3);
    D2 = Dxi(1,4)+ Dxi(2,5) + Dxi(3,6) + 2*Dxy(1,4,2,5) + 2*Dxy(1,4,3,6) + 2*Dxy(2,5,3,6);
    D3 = Dxi(1,7)+ Dxi(2,8) + Dxi(3,9) + 2*Dxy(1,7,2,8) + 2*Dxy(1,7,3,9) + 2*Dxy(2,8,3,9);
    
    D = [D1;D2;D3];
    
end
D = alphaVolume*D;


function D = getDiagArea(Mesh,yc,alphaArea)
%dim = Mesh.dim;
vol = Mesh.vol;

dphi = Mesh.dphi;    
%dphi1 = dphi{1}; dphi2 = dphi{2}; dphi3 = dphi{3}; dphi4 = dphi{4};

[cof, ~] = cofactor3D([],Mesh,0,1);
yc = reshape(yc,[],3);
% compute areas
area = [
        cof{1}(yc).^2+cof{4}(yc).^2+cof{7}(yc).^2;
        cof{2}(yc).^2+cof{5}(yc).^2+cof{8}(yc).^2;
        cof{3}(yc).^2+cof{6}(yc).^2+cof{9}(yc).^2;
        ];    
% compute penalty
[~,~,d2H] = phiDW(area,1);
d2H = reshape(d2H,[],3);

dx{1}.D = Mesh.mfdx1.D; dx{1}.Dadj = Mesh.mfdx1.Dadj;
dx{2}.D = Mesh.mfdx2.D; dx{2}.Dadj = Mesh.mfdx2.Dadj;
dx{3}.D = Mesh.mfdx3.D; dx{3}.Dadj = Mesh.mfdx3.Dadj;

D = @(i,j) dx{i}.D(yc(:,j));
%dA = 2*(cof{i}(yc)*dCof{i}+sdiag(cof(:,i+3))*dCof{i+3}+sdiag(cof(:,i+6))*dCof{i+6});
%vol.*d2H(:,i))*dA;

% dCof{1} = [  Z                 , D(3,3)*D2-D(2,3)*D3, D(2,2)*D3-D(3,2)*D2];
% dCof{2} = [  Z                 , D(1,3)*D3-D(3,3)*D1, D(3,2)*D1-D(1,2)*D3];
% dCof{3} = [  Z                 , D(2,3)*D1-D(1,3)*D2, D(1,2)*D2-D(2,2)*D1];
% dCof{4} = [ D(2,3)*D3-D(3,3)*D2, Z                  , D(3,1)*D2-D(2,1)*D3];
% dCof{5} = [ D(3,3)*D1-D(1,3)*D3, Z                  , D(1,1)*D3-D(3,1)*D1];
% dCof{6} = [ D(1,3)*D2-D(2,3)*D1, Z                  , D(2,1)*D1-D(1,1)*D2];
% dCof{7} = [ D(3,2)*D2-D(2,2)*D3, D(2,1)*D3-D(3,1)*D2, Z];
% dCof{8} = [ D(1,2)*D3-D(3,2)*D1, D(3,1)*D1-D(1,1)*D3, Z];
% dCof{9} = [ D(2,2)*D1-D(1,2)*D2, D(1,1)*D2-D(2,1)*D1, Z];
Z = zeros(Mesh.ntri,1);
dCof{1} = @(j) [  Z                                         , D(3,3).*dphi{j}(:,2)-D(2,3).*dphi{j}(:,3), D(2,2).*dphi{j}(:,3)-D(3,2).*dphi{j}(:,2)];
dCof{2} = @(j) [  Z                                         , D(1,3).*dphi{j}(:,3)-D(3,3).*dphi{j}(:,1), D(3,2).*dphi{j}(:,1)-D(1,2).*dphi{j}(:,3)];
dCof{3} = @(j) [  Z                                         , D(2,3).*dphi{j}(:,1)-D(1,3).*dphi{j}(:,2), D(1,2).*dphi{j}(:,2)-D(2,2).*dphi{j}(:,1)];
dCof{4} = @(j) [ D(2,3).*dphi{j}(:,3)-D(3,3).*dphi{j}(:,2)  , Z                                        , D(3,1).*dphi{j}(:,2)-D(2,1).*dphi{j}(:,3)];
dCof{5} = @(j) [ D(3,3).*dphi{j}(:,1)-D(1,3).*dphi{j}(:,3)  , Z                                        , D(1,1).*dphi{j}(:,3)-D(3,1).*dphi{j}(:,1)];
dCof{6} = @(j) [ D(1,3).*dphi{j}(:,2)-D(2,3).*dphi{j}(:,1)  , Z                                        , D(2,1).*dphi{j}(:,1)-D(1,1).*dphi{j}(:,2)];
dCof{7} = @(j) [ D(3,2).*dphi{j}(:,2)-D(2,2).*dphi{j}(:,3)  , D(2,1).*dphi{j}(:,3)-D(3,1).*dphi{j}(:,2), Z];
dCof{8} = @(j) [ D(1,2).*dphi{j}(:,3)-D(3,2).*dphi{j}(:,1)  , D(3,1).*dphi{j}(:,1)-D(1,1).*dphi{j}(:,3), Z];
dCof{9} = @(j) [ D(2,2).*dphi{j}(:,1)-D(1,2).*dphi{j}(:,2)  , D(1,1).*dphi{j}(:,2)-D(2,1).*dphi{j}(:,1), Z];
    
% vol.*d2H(:,i))*2*cof{i}(yc)*dCof{i}

coeff = @(i,j)  4.*vol.*d2H(:,i).*cof{j}(yc).^2;

Dxi = @(i,j) Mesh.mfPi(coeff(i,j).*dCof{j}(1).^2,1) ... 
        + Mesh.mfPi(coeff(i,j).*dCof{j}(2).^2,2) ...
        + Mesh.mfPi(coeff(i,j).*dCof{j}(3).^2,3) ...
        + Mesh.mfPi(coeff(i,j).*dCof{j}(4).^2,4); % diagonal of Dxi'*Dxi 
    
coeff2 = @(i,j,k)  4.*vol.*d2H(:,i).*cof{j}(yc).*cof{k}(yc);
    
Dxy = @(i,j,k) Mesh.mfPi(coeff2(i,j,k).*dCof{j}(1).*dCof{k}(1),1) ... 
             + Mesh.mfPi(coeff2(i,j,k).*dCof{j}(2).*dCof{k}(2),2) ...
             + Mesh.mfPi(coeff2(i,j,k).*dCof{j}(3).*dCof{k}(3),3) ...
             + Mesh.mfPi(coeff2(i,j,k).*dCof{j}(4).*dCof{k}(4),4); % diagonal of Dxi'*Dxi 

D = zeros(Mesh.nnodes,3);
for i=1:3
    D = D + Dxi(i,i) + Dxi(i,i+3) + Dxi(i,i+6) + 2*Dxy(i,i,i+3) + 2*Dxy(i,i,i+6) + 2*Dxy(i,i+3,i+6);
end

D = alphaArea*D(:);




% compute d2Svol*x
% function By = volumeOperator(yc,Mesh,x,vol)
% [dx1, dx2] = getGradientMatrixFEM(Mesh,1);
% % volume regularization
% yc = reshape(yc,[],2);
% By = [dx1.D(yc(:,1))  dx2.D(yc(:,1)) dx1.D(yc(:,2)) dx2.D(yc(:,2))];
% det = By(:,1).*By(:,4) - By(:,3) .* By(:,2);
% [~,~,d2G] = psi(det,1);
% 
% %      MB : dDet = [sdiag(By(:,4)), sdiag(-By(:,3)) , sdiag(-By(:,2)), sdiag(By(:,1))] * B;
% 
% dDet  = @(x)   By(:,4).*dx1.D(x(:,1))- By(:,3).*dx2.D(x(:,1))...
%     -By(:,2).*dx1.D(x(:,2))+By(:,1).*dx2.D(x(:,2));
% 
% dDetAdj  = @(x) [ ...
%     dx1.Dadj(By(:,4).*x)-dx2.Dadj(By(:,3).*x);...
%     -dx1.Dadj(By(:,2).*x)+dx2.Dadj(By(:,1).*x)
%     ];
% By = dDetAdj(vol.*d2G.*dDet(reshape(x,[],2)));



function D = getDiagLength(Mesh,alphaLength)
dim = Mesh.dim;
vol = Mesh.vol;
if dim==2
    
    dphi  = Mesh.dphi;    
    dphi1 = dphi{1}; dphi2 = dphi{2}; dphi3 = dphi{3};
    
    % get boundaries
    Dxi = @(i) Mesh.mfPi(vol.*dphi1(:,i).^2,1) + Mesh.mfPi(vol.*dphi2(:,i).^2,2) + Mesh.mfPi(vol.*dphi3(:,i).^2,3); % diagonal of Dx1'*Dx1
        
    D = Dxi(1)+ Dxi(2);
    D = [D;D];
else
    dphi  = Mesh.dphi;    
    dphi1 = dphi{1}; dphi2 = dphi{2}; dphi3 = dphi{3}; dphi4 = dphi{4};
    
    % get boundaries
    Dxi = @(i) Mesh.mfPi(vol.*dphi1(:,i).^2,1) + ...
                Mesh.mfPi(vol.*dphi2(:,i).^2,2) + ...
                    Mesh.mfPi(vol.*dphi3(:,i).^2,3) + ...
                        Mesh.mfPi(vol.*dphi4(:,i).^2,4); % diagonal of Dx1'*Dx1
        
    D = Dxi(1)+ Dxi(2) + Dxi(3);
    D = [D;D;D];

end
D = alphaLength*D(:);


function [G dG d2G] = psi(x,doDerivative)
%
% psi(x) = ((x-1)^2/x)^2
%
% psi satisfies the three important conditions
%      psi(x) > 0, forall x
%      psi(1) = 0
%      psi is convex
%      psi(x) = psi(1/x)
%      psi yields det(Dy) in L_2
dG = [];
d2G = [];

G = (x-1).*(x-1) ./x;
G = G.*G;
if doDerivative,
    dG  = 2* (x-1).^3 .* (x+1)./ x.^3;
    d2G = 2* (x.^4-4*x+3) ./ x.^4;
end

function [G dG d2G] = phiC(x,doDerivative)
%
%   phiC is a convex penalty function for surface area
%   regularization. This function is needed in the existence proof. In
%   order to be convex, only area growth can be penalized
%
%
%    phi(x>=1) = 0.5 * (A/ ARef - 1)^2
%    phi(x<1 ) = 0
%
%    A    - area after deformation (24 Triangles per voxel, scalar)
%    ARef - area of reference configuration (24 Triangles per voxel, scalar)
%
dG = [];
d2G = [];
G = 0.5* (x-1).*(x-1);
G(x<1)=0;
if doDerivative,
    dG = (x-1);
    dG(x<1)=0;
    d2G = ones(size(dG));
    d2G(x<1)=0;
end

function [G dG d2G] = phiDW(x,doDerivative)
%
%   phiDW is a penalty function for surface area
%   regularization that penalizes growth and shrinkage of area. However,
%   this function is a double well and thus not convex.
%
%    phi(A) = 0.5 * (A/ ARef - 1)^2
%
%    A    - area after deformation (24 Triangles per voxel, scalar)
%    ARef - area of reference configuration (24 Triangles per voxel, scalar)
dG = [];
d2G = [];
G = 0.5* (x-1).*(x-1);
if doDerivative,
    dG = (x-1);
    d2G = ones(size(dG));
end

% shortcut for spdiags
function D = sdiag(v)
D = spdiags(v(:),0,numel(v),numel(v));

function runMinimalExample
%========= 2D
omega = [0,10,0,8]; m = [17,16]; p = [5,6];
w = zeros([p,2]);  w(3,3,1) = 0.06; w(3,4,2) = -0.05;
Mesh   = TriMesh1(omega,m);
xn = Mesh.xn;
yn = splineTransformation2D(w(:),xn(:),'omega',omega,'m',m+1,'p',p,'Q',[]);

regOptn = {'alpha',1,'alphaLength',0,'alphaArea',0,'alphaVolume',1};

fctn = @(y) feval(mfilename,y-xn(:),xn(:),Mesh,regOptn{:},'matrixFree',0);
[Sc, dS, d2S] = fctn(yn(:));
checkDerivative(fctn,yn(:));

%========== 3D
omega = [0,10,0,8,0 4]; m = [5,6,8]; type = 1;
%omega = [0,5,0,5,0 5]; m = [5,5,5]; type = 1;
Mesh = TetraMesh1(omega,m);
xn = Mesh.xn;
yn = xn + 1e-1* randn(size(xn));

regOptn = {'alpha',1,'alphaLength',0,'alphaArea',0,'alphaVolume',1};

fctn = @(y) feval(mfilename,y-xn(:),xn(:),Mesh,regOptn{:},'matrixFree',0);
[Sc, dS, d2S] = fctn(yn(:));
checkDerivative(fctn,yn(:));

fctn = @(y) feval(mfilename,y-xn(:),xn(:),Mesh,regOptn{:},'matrixFree',1);
[ScMF, dSMF, d2SMF] = fctn(yn(:));

% error MB - MF 
errdS = norm(dS - dSMF)

z = rand(3*Mesh.nnodes,1);
errd2S = norm(d2S*z - d2SMF.d2S(z))

errDiag = norm(diag(d2S) - d2SMF.diag(yn))

ans




