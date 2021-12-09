classdef TBG < handle
    %UNTITLED3 Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        theta = 0;
        m=1;
        n=1;
        a0=1;
        c0=3;
        a;
        A;              % Superlattice lattice vectors
        B;              % Reciprocal lattice vectors
        p;         % p(:,:,1) and p(:,:,2) are the coordinates lattice points on layer 1 and 2 respectively
        c;         % c(:,:,1), c(:,:,2) are atom coordinates on layer 1 and 2
        hintra;         % Cell array storing adjacent vectors and hopping energy
        hinter;
        N;
        
        A0;    % Hopping cutoff distance
        Vpi=-2.7;
        Vsigma=0.48;        % Hopping energy for pi and sigma bonding
        %Vsigma=0;
        delta;              % Hopping energy decaying discance
        MAXK=50;          % Max hopping neighbors
        H0;
    end
    
    methods
        function tbg = TBG(n, m, varargin)
            tbg.a0 = 0.142/197;
            tbg.A0 = 4.01*tbg.a0;
            tbg.delta = 0.184*tbg.a0;
            tbg.c0 = 0.335/197;
            tbg.n = n;
            tbg.m = m;
            tbg.theta = acos((n^2+4*m*n+m^2)/(2*(n^2+n*m+m^2)))*sign(n-m);
            a1 = [1.5; -0.5*sqrt(3)] * tbg.a0;
            a2 = [1.5; 0.5*sqrt(3)] * tbg.a0;
            R1 = [cos(tbg.theta/2), -sin(tbg.theta/2); sin(tbg.theta/2), cos(tbg.theta/2)];
            R2 = [cos(tbg.theta/2), sin(tbg.theta/2); -sin(tbg.theta/2), cos(tbg.theta/2)];
            A1 = R1 * ( n*a1 + m*a2);
            A2 = R1 * (-m*a1 + (n+m)*a2);
            B1 = 2*pi/sum(cross([A1;0],[A2;0]))*cross([A2;0],[0;0;1]);B1 = B1(1:2);
            B2 = 2*pi/sum(cross([A1;0],[A2;0]))*cross([0;0;1],[A1;0]);B2 = B2(1:2);
            a11 = R1 * a1;
            a21 = R1 * a2;
            a12 = R2 * a1;
            a22 = R2 * a2;
            tbg.A = [A1, A2];
            tbg.B = [B1, B2];
            tbg.a = [a1, a2];
            
            p1 = find_points(tbg, n, m, a11, a21);
            p2 = find_points(tbg, m, n, a12, a22);
            
            assert(size(p1,1) == n^2+m^2+n*m);
            assert(size(p2,1) == n^2+m^2+n*m);
            
            tbg.p(:,:,1) = p1;
            tbg.p(:,:,2) = p2;
            
            tbg.N = n^2+m^2+n*m;
            T = inv(tbg.A); % Transformation from real coordinates to lattice coordinates
            c1 = [tbg.p(:,:,1) + 1/3 * repmat((a11 + a21)',tbg.N,1);tbg.p(:,:,1) - 1/3 * repmat((a11 + a21)',tbg.N,1)]; % Real coordinates of atoms in layer 1
%             c2 = [tbg.p(:,:,2);tbg.p(:,:,2) - 1/3 * repmat((a12 + a22)',tbg.N,1)]; % and layer 2 (Bernal-stacked when theta=0)
            c2 = [tbg.p(:,:,2) + 1/3 * repmat((a12 + a22)',tbg.N,1);tbg.p(:,:,2) - 1/3 * repmat((a12 + a22)',tbg.N,1)]; % and layer 2 (Bernal-stacked when theta=0)
            C1 = mod(c1*T', 1); % Transform to lattice coordinates and move everything back to the unit cell
            C2 = mod(c2*T', 1);
            tbg.c(:,:,1) = C1*tbg.A'; % Transform back to real coordinates
            tbg.c(:,:,2) = C2*tbg.A';
            
            if nargin==2 || varargin{1}
                calcHopping(tbg);
            end
            
            
            disp('Twisted bilayer graphene initialized');
            disp(['Twist angle: ',num2str(tbg.theta/pi*180),' degrees']);
            disp(['Superlattice potential period: ',num2str(norm(A1)*197/abs(n-m)),' nm']);
            
        end
        
        function [E, P]=getDispersion(tbg, kx, ky, V1, V2)
            NK = numel(kx);              % Number of k points
            kx=kx(:);% reshape different k values to the first dimension
            ky=ky(:);
            k=[kx,ky];
            if V1~=0
                % add external potential
                H=repmat(shiftdim(diag([repmat(-V1/2,2*tbg.N,1);repmat(V1/2,2*tbg.N,1)]),-1),[NK,1,1]);
            else
                H=zeros(NK, 4*tbg.N, 4*tbg.N);
            end
            if(V2~=0)
                % V2 adds a asymmetry to the sublattice
                
                % Use this for adding the same amount to both layers
                %H=H + repmat(shiftdim(diag([repmat(-V2/2,tbg.N,1);repmat(V2/2,tbg.N,1);repmat(-V2/2,tbg.N,1);repmat(V2/2,tbg.N,1)]),-1),[NK,1,1]);
                
                % Use this to add only to one layer, i.e. graphene/h-BN
                H=H + repmat(shiftdim(diag([repmat(-V2/2,tbg.N,1);repmat(V2/2,tbg.N,1);zeros(tbg.N,1);zeros(tbg.N,1)]),-1),[NK,1,1]);
            end
            H=double(H); % Truncate precision to save memory
            
            % hop: p*2 array (p is number of neighbors). pos: index of
            % current atom. layer: index of current layer (0 or 1)
            function map(hop, pos, layer1, layer2)
                %H(:, pos+layer1*2*tbg.N, hop(:,1)+layer2*2*tbg.N) = ...
                %    H(:, pos+layer1*2*tbg.N, hop(:,1)+layer2*2*tbg.N) + reshape(exp(1i*(k*hop(:,3:4)')).*repmat(hop(:,2)',NK,1), NK, 1, []);
                %disp([num2str(pos),',',num2str(layer1),',',num2str(layer2)]);
                for j=1:size(hop,1)
                    H(:, pos+layer1*2*tbg.N, hop(j,1)+layer2*2*tbg.N) = ...
                        H(:, pos+layer1*2*tbg.N, hop(j,1)+layer2*2*tbg.N) + exp(1i*(k*hop(j,3:4)'))*hop(j,2);
                end
            end
            fprintf('Map 1\n');
            cellfun(@map, tbg.hintra(:,1), num2cell((1:2*tbg.N)'), num2cell(zeros(2*tbg.N,1)), num2cell(zeros(2*tbg.N,1))); % Map intralayer hoppings to the upper-left quadrant of the hamiltonian
            fprintf('Map 2\n');
            cellfun(@map, tbg.hintra(:,2), num2cell((1:2*tbg.N)'), num2cell(ones(2*tbg.N,1)), num2cell(ones(2*tbg.N,1))); % Map intralayer hoppings to the lower-right quadrant of the hamiltonian
            fprintf('Map 3\n');
            cellfun(@map, tbg.hinter(:,1), num2cell((1:2*tbg.N)'), num2cell(zeros(2*tbg.N,1)), num2cell(ones(2*tbg.N,1))); % Map interlayer hoppings to the upper-right quadrant of the hamiltonian
            fprintf('Map 4\n');
            cellfun(@map, tbg.hinter(:,2), num2cell((1:2*tbg.N)'), num2cell(ones(2*tbg.N,1)), num2cell(zeros(2*tbg.N,1))); % Map interlayer hoppings to the lower-left quadrant of the hamiltonian
            fprintf('Hermitianize\n');
            H = (H + conj(permute(H,[1,3,2])))/2; % Force H to be hermitian, so that the eigen problem can be solved MUCH FASTER
            %tbg.H0=H;
            disp('Hamiltonian Constructed and Hermitianized');
            % Now we have the Hamiltonian. Solve it! (for each k)
            E = double(zeros(NK, 4*tbg.N));
            P = double(zeros(NK, 4*tbg.N, 4*tbg.N));
            %E = zeros(NK, 20);
            for i=1:NK
                starttime=datetime;
                fprintf('%d start...',i);
                [V1,D]=eig(squeeze(H(i,:,:)));
                [E(i,:), I] = sort(real(diag(D)));
                P(i,:,:) = V1(:, I);
                fprintf('ended in');
                disp(datetime-starttime);
            end
        end
        
        % Get eigenvalue and eigen state at a specified k point
        % Input is fraction of reciprocal lattice vector
        function D=getState(tbg, skx, sky, V1, V2)
            K = tbg.B(:,1) * skx + tbg.B(:,2) * sky;
            [D.E, D.P] = tbg.getDispersion(K(1), K(2), V1, V2);
        end
        
        % Get dispersion in the first Brillouin zone
        function D=getBrillouin(tbg, res, div, V1, V2, saveState)
            B1 = tbg.B(:,1);
            B2 = tbg.B(:,2);
%             [px,py] = meshgrid(linspace(0,1,res),linspace(0,1,res));
%             kx = px * B1(1) + py * B2(1);
%             ky = px * B1(2) + py * B2(2);
%             D.kx = kx;
%             D.ky = ky;
%             D.E = tbg.getDispersion(kx,ky,V);
            
            K = 2/3 * [1;0] + 1/3 * [-1/2;sqrt(3)/2];
            Kp = 1/3 * [1;0] + 2/3 * [-1/2;sqrt(3)/2];
            %pv=[K,[0;0],[0.5;0],K]';
            %pv=[[0;0],[1;0],[0.5;sqrt(3)/2],[-0.5;sqrt(3)/2],[0;0]]';
            pv=[K,Kp,[-K(1);K(2)],-K,-Kp,[K(1);-K(2)],K]';
            %fh=@(p,a) min(min(0.5/res+5/res*abs(dcircle(p,K(1),K(2),0)),0.5/res+5/res*abs(dcircle(p,Kp(1),Kp(2),0))), 5/res);
            fh=@(p,a) min(min(min(min(min(min(min(...
                    0.5/res+5/res*abs(dcircle(p,K(1),K(2),0)),...
                    0.5/res+5/res*abs(dcircle(p,Kp(1),Kp(2),0))),...
                    0.5/res+5/res*abs(dcircle(p,-K(1),K(2),0))),...
                    0.5/res+5/res*abs(dcircle(p,-K(1),-K(2),0))),...
                    0.5/res+5/res*abs(dcircle(p,-Kp(1),-Kp(2),0))),...
                    0.5/res+5/res*abs(dcircle(p,K(1),-K(2),0))),...
                    0.5/res+5/res*abs(dcircle(p,0,0,0))),...
                    5/res);
            [pt,tri]=distmesh2d(@dpoly,fh,0.5/res, [-0.5,-sqrt(3)/3;0.5,sqrt(3)/3], pv, pv);
            T1 = [1, -1/2; 0, sqrt(3)/2];
            T2 = [B1, B2];
            k = T2 / T1 * pt';
            kx = k(1,:)';
            ky = k(2,:)';
            D.kx = kx;
            D.ky = ky;
            D.fn=@(p) dpoly(p, pv);
            triplot(tri,kx,ky);
            fprintf('# of points: %d\n', length(kx));
            if div == 0
                if(saveState)
                    [D.E, D.P] = tbg.getDispersion(kx,ky,V1,V2);
                else 
                    [D.E, ~] = tbg.getDispersion(kx,ky,V1,V2);
                end
            else
                i=1;
                D.E = double(zeros(length(kx), 4*tbg.N));
                if(saveState)
                    D.P = double(zeros(length(kx), 4*tbg.N, 4*tbg.N));
                end
                while i<=length(kx)
                    if(saveState)
                        [D.E(i:min(i+div-1,length(kx)), :),D.P(i:min(i+div-1,length(kx)), :, :)] = tbg.getDispersion(kx(i:min(i+div-1,length(kx))), ky(i:min(i+div-1,length(kx))), V1);
                    else
                        [D.E(i:min(i+div-1,length(kx)), :),~] = tbg.getDispersion(kx(i:min(i+div-1,length(kx))), ky(i:min(i+div-1,length(kx))), V1, V2);
                    end
                    i = i+div;
                    fprintf('%g%% finished\n', max(i,length(kx))/length(kx)*100);
                end
            end
            D.B = tbg.B;
            D.t = tri;
            %D.E = reshape(D.E, length(kx), []);
            plotDispersion(D);
        end
        
        % Get dispersion on high symmetrical points and lines
        function D=getHighSymmetrical(tbg, res, div, V1, V2)
           B1 = tbg.B(:,1);
           B2 = tbg.B(:,2);
           K  = (2/3 * B1 + 1/3 * B2)';
           Kp = (1/3 * B1 + 2/3 * B2)';
           Gamma = [0,0];
           M = (K + Kp) / 2;
           t=linspace(0,1,res+1)'; t=t(1:end-1);
           % K -- Gamma
           kxy = repmat(K, res, 1) + t * (Gamma - K);
           T = t * norm(Gamma - K);
           % Gamma -- M
           kxy = [kxy ; repmat(Gamma, res, 1) + t * (M - Gamma)];
           T = [T; norm(Gamma - K) + t * norm(M - Gamma)];
           % M -- Kp
           kxy = [kxy ; repmat(M, res, 1) + t * (Kp - M)];
           T = [T; norm(Gamma - K) + norm(M - Gamma) + t * norm(Kp - M)];
           % Kp
           kxy = [kxy ; Kp];
           T = [T; norm(Gamma - K) + norm(M - Gamma) + norm(Kp - M)];
           
           kx = kxy(:,1);
           ky = kxy(:,2);
           i=1;
           D.E = zeros(size(kx,1), 4*tbg.N);
           while i<=size(kx,1)             
                [D.E(i:min(i+div-1,size(kx,1)), :),~] = tbg.getDispersion(kx(i:min(i+div-1,size(kx,1))), ky(i:min(i+div-1,size(kx,1))), V1, V2);
                i = i + div;
           end
           D.kx = kx;
           D.ky = ky;
           D.t = T;
           plotHighSymmetric(D);
        end
        % find all possible lattice coordinates in a superlattice. Basic
        % idea: In a TBG, the SUPERLATTICE BASE VECTORS corresponds to (n,
        % m) and (-m, n+m) in LAYER 1 (rotated counterclockwise for
        % theta/2). It corresponds to (m,n) and (-n, n+m) in LAYER 2
        % (rotated clockwise for theta/2). The purpose of this function is
        % to find out what possible combinations of (n',m') are inside the
        % region defined by the superlattice base vectors. The result
        % should contain exactly n^2+m^2+nm points. For LAYER 1, pass n, m
        % to this function and m, n for LAYER 2. a1 and a2 should be set to
        % the base vector of the corresponding layer.
        function points = find_points(~, p, q, a1, a2)
            % P and Q stores all possible points in lattice coordinates
            [P, Q] = meshgrid(-q:p, 0:(p+2*q));
            r = p^2 + q^2 + p*q;
            % The linear transformation transforms the permitted area into
            % a unit square
            P1 = ((p+q) * P + q * Q) ./ r;
            Q1 = (   -q * P + p * Q) ./ r;
            % Now rule out those points that are not in the unit square
            % after transformation
            In = (P1 >= 0) & (P1 < 1)...
            & (Q1 >= 0) & (Q1 < 1);
            % Convert the lattice coordinates back to real coordinates
            % using provided base vector
            points = P(In) * a1' + Q(In) * a2';
            disp('Complete');
        end
        
        function calcHopping(tbg)
            tbg.hinter = cell(2*tbg.N,2);% (i,j,k) i: atom index j: index/distance k:layer index
            tbg.hintra = cell(2*tbg.N,2);
            A1 = tbg.A(:,1)';
            A2 = tbg.A(:,2)';
            E1 = [tbg.c(:,:,1);...
                  tbg.c(:,:,1)+repmat(A1, 2*tbg.N, 1);...
                  tbg.c(:,:,1)+repmat(A1+A2, 2*tbg.N, 1);...
                  tbg.c(:,:,1)+repmat(A1-A2, 2*tbg.N, 1);...
                  tbg.c(:,:,1)+repmat(A2, 2*tbg.N, 1);...
                  tbg.c(:,:,1)+repmat(-A2, 2*tbg.N, 1);...
                  tbg.c(:,:,1)+repmat(-A1, 2*tbg.N, 1);...
                  tbg.c(:,:,1)+repmat(-A1-A2, 2*tbg.N, 1);...
                  tbg.c(:,:,1)+repmat(-A1+A2, 2*tbg.N, 1);...
                  ];
              
            E2 = [tbg.c(:,:,2);...
                  tbg.c(:,:,2)+repmat(A1, 2*tbg.N, 1);...
                  tbg.c(:,:,2)+repmat(A1+A2, 2*tbg.N, 1);...
                  tbg.c(:,:,2)+repmat(A1-A2, 2*tbg.N, 1);...
                  tbg.c(:,:,2)+repmat(A2, 2*tbg.N, 1);...
                  tbg.c(:,:,2)+repmat(-A2, 2*tbg.N, 1);...
                  tbg.c(:,:,2)+repmat(-A1, 2*tbg.N, 1);...
                  tbg.c(:,:,2)+repmat(-A1-A2, 2*tbg.N, 1);...
                  tbg.c(:,:,2)+repmat(-A1+A2, 2*tbg.N, 1);...
                  ];
            [idx11, d11] = knnsearch(E1, tbg.c(:,:,1), 'K', tbg.MAXK+1);
            [idx22, d22] = knnsearch(E2, tbg.c(:,:,2), 'K', tbg.MAXK+1);
            [idx12, d12] = knnsearch(E2, tbg.c(:,:,1), 'K', tbg.MAXK);
            [idx21, d21] = knnsearch(E1, tbg.c(:,:,2), 'K', tbg.MAXK);
            d12 = sqrt(d12.^2 + tbg.c0^2);
            d21 = sqrt(d21.^2 + tbg.c0^2);
            C11 = cat(3, mod(idx11(:,2:end)-1, 2*tbg.N)+1, d11(:,2:end), reshape(E1(reshape(idx11(:,2:end),[],1), :)-tbg.c(repmat((1:2*tbg.N)',size(idx11,2)-1,1),:,1), 2*tbg.N, [], 2));
            C22 = cat(3, mod(idx22(:,2:end)-1, 2*tbg.N)+1, d22(:,2:end), reshape(E2(reshape(idx22(:,2:end),[],1), :)-tbg.c(repmat((1:2*tbg.N)',size(idx22,2)-1,1),:,2), 2*tbg.N, [], 2));
            C12 = cat(3, mod(idx12-1, 2*tbg.N)+1, d12, reshape(E2(reshape(idx12,[],1), :)-tbg.c(repmat((1:2*tbg.N)',size(idx12,2),1),:,1), 2*tbg.N, [], 2));
            C21 = cat(3, mod(idx21-1, 2*tbg.N)+1, d21, reshape(E1(reshape(idx21,[],1), :)-tbg.c(repmat((1:2*tbg.N)',size(idx21,2),1),:,2), 2*tbg.N, [], 2));
            cell11 = cellfun(@(X) num2cell(squeeze(X(1,X(1,:,2)<tbg.A0,:)),[1,2]), num2cell(C11, [2,3])); % Each row is combined into a cell, and filtered with A0
            cell22 = cellfun(@(X) num2cell(squeeze(X(1,X(1,:,2)<tbg.A0,:)),[1,2]), num2cell(C22, [2,3])); % Each row is combined into a cell, and filtered with A0
            cell12 = cellfun(@(X) num2cell(squeeze(X(1,X(1,:,2)<tbg.A0,:)),[1,2]), num2cell(C12, [2,3])); % Each row is combined into a cell, and filtered with A0
            cell21 = cellfun(@(X) num2cell(squeeze(X(1,X(1,:,2)<tbg.A0,:)),[1,2]), num2cell(C21, [2,3])); % Each row is combined into a cell, and filtered with A0
            function out=intrahop(in) % convert distance to hopping energy
                in(:,2)=tbg.Vpi*exp(-(in(:,2)-tbg.a0)./tbg.delta);  % Only pi bonding in intralayer hopping
                out=num2cell(in, [1,2]);
            end
            function out=interhop(in) % convert distance to hopping energy
                in(:,2)=tbg.Vpi*exp(-(in(:,2)-tbg.a0)./tbg.delta).*(1 - (tbg.c0./in(:,2)).^2)...  % PI bonding in intralayer hopping
                   +tbg.Vsigma*exp(-(in(:,2)-tbg.c0)./tbg.delta).*(tbg.c0./in(:,2)).^2;  
                out=num2cell(in, [1,2]);
            end
            cell11 = cellfun(@intrahop, cell11);
            cell22 = cellfun(@intrahop, cell22);
            cell12 = cellfun(@interhop, cell12);
            cell21 = cellfun(@interhop, cell21);
            tbg.hintra(:, 1) = cell11;  % The first element is always itself for intralayer. Remove it
            tbg.hintra(:, 2) = cell22;
            tbg.hinter(:, 1) = cell12;
            tbg.hinter(:, 2) = cell21;
        end
        
        function plot(tbg)
%             N = tbg.n+tbg.m;
%             a = tbg.a0;
%             th = tbg.theta;
%             R1 = [cos(th/2), -sin(th/2); sin(th/2), cos(th/2)];
%             R2 = [cos(th/2), sin(th/2); -sin(th/2), cos(th/2)];
%             c1 = 1.5 * a;
%             c2 = sqrt(3) / 2 * a;
%             c3 = 0.5 * a;
            
%             figure;
%             axis equal tight;
%             hold on;
%             for i=-max(tbg.n, tbg.m)-2:max(tbg.n, tbg.m)+2
%                 for j=-2:2*N
%                     % Convert lattice coordinate to space coordinate
%                     x = c1 * double(i + j);
%                     y = c2 * double(j - i);
%                     p1 = [x;y] + [-a; 0];
%                     p2 = [x;y] + [-c3; c2];
%                     p3 = [x;y] + [c3; c2];
%                     p4 = [x;y] + [a; 0];
%                     line1 = [R1*p1, R1*p2, R1*p3, R1*p4];
%                     line2 = [R2*p1, R2*p2, R2*p3, R2*p4];
%                     plot(line1(1,:), line1(2,:), 'k', line2(1,:), line2(2,:), 'k');
%                 end
%             end
%             
             t1 = tbg.A(:,1);
             t2 = tbg.A(:,2);          
%             plot([0; t1(1)], [0; t1(2)], 'g', 'LineWidth', 1.5);
%             plot([0; t2(1)], [0; t2(2)], 'g', 'LineWidth', 1.5);
%             plot([t1(1); t1(1) + t2(1)], [t1(2); t1(2) + t2(2)], 'g', 'LineWidth', 1.5);
%             plot([t2(1); t1(1) + t2(1)], [t2(2); t1(2) + t2(2)], 'g', 'LineWidth', 1.5);
%             hold off
            figure
            axis equal tight
            title 'Lattice Positions'
            hold on
            plot([0; t1(1)], [0; t1(2)], 'g', 'LineWidth', 1.5);
            plot([0; t2(1)], [0; t2(2)], 'g', 'LineWidth', 1.5);
            plot([t1(1); t1(1) + t2(1)], [t1(2); t1(2) + t2(2)], 'g', 'LineWidth', 1.5);
            plot([t2(1); t1(1) + t2(1)], [t2(2); t1(2) + t2(2)], 'g', 'LineWidth', 1.5);
            scatter(tbg.p(:,1,1), tbg.p(:,2,1),36, 'red');
            scatter(tbg.p(:,1,2), tbg.p(:,2,2),36, 'blue');
            hold off;
            figure
            axis equal tight
            title 'Atom Positions'
            hold on
            plot([0; t1(1)], [0; t1(2)], 'g', 'LineWidth', 1.5);
            plot([0; t2(1)], [0; t2(2)], 'g', 'LineWidth', 1.5);
            plot([t1(1); t1(1) + t2(1)], [t1(2); t1(2) + t2(2)], 'g', 'LineWidth', 1.5);
            plot([t2(1); t1(1) + t2(1)], [t2(2); t1(2) + t2(2)], 'g', 'LineWidth', 1.5);
            plot([(t1(1)+t2(1))/3; (t1(1)+t2(1))*2/3], [(t1(2)+t2(2))/3; (t1(2)+t2(2))*2/3], 'b', 'LineWidth', 1.5);
            plot([t1(1); t2(1)], [t1(2); t2(2)], 'b', 'LineWidth', 1.5);
            scatter3(tbg.c(:,1,1), tbg.c(:,2,1),zeros(tbg.N*2,1),36, 'r^');
            scatter3(tbg.c(:,1,2), tbg.c(:,2,2),repmat(tbg.c0,tbg.N*2,1),36, 'blue');
            hold off;
            
            TBG.plotadj(tbg.c(:,:,1),tbg.c(:,:,1),tbg.hintra(:,1),0,'Layer 1 intra');
            TBG.plotadj(tbg.c(:,:,2),tbg.c(:,:,2),tbg.hintra(:,2),0,'Layer 2 intra');
            TBG.plotadj(tbg.c(:,:,1),tbg.c(:,:,2),tbg.hinter(:,1),1,'Layer 1 -> 2 inter');
            TBG.plotadj(tbg.c(:,:,2),tbg.c(:,:,1),tbg.hinter(:,2),1,'Layer 2 -> 1 inter');
            
            figure
            title 'Brillouin Zone'
            hold on
            axis equal tight
            K1=K(tbg.a0,tbg.theta/2);
            K2=K(tbg.a0,-tbg.theta/2);
            for i=1:6
                K1n=[0.5,-0.5*sqrt(3); 0.5*sqrt(3), 0.5]*K1;
                K2n=[0.5,-0.5*sqrt(3); 0.5*sqrt(3), 0.5]*K2;
                plot([K1(1),K1n(1)],[K1(2),K1n(2)],'r');
                plot([K2(1),K2n(1)],[K2(2),K2n(2)],'b');
                K1=K1n;
                K2=K2n;
            end
            kc=K(tbg.a0,tbg.theta/2)-tbg.B(:,1)*2/3-tbg.B(:,2)/3;
            Ks=tbg.B(:,1)*2/3+tbg.B(:,2)/3;
            for i=1:6
                Ksn=[0.5,-0.5*sqrt(3); 0.5*sqrt(3), 0.5]*Ks;
                plot([Ks(1)+kc(1),Ksn(1)+kc(1)],[Ks(2)+kc(2),Ksn(2)+kc(2)],'g','LineWidth',1.5);
                Ks=Ksn;
            end
            hold off
        end
    end
    methods(Static)
        function plotadj(c1,c2,h,inter,tit)
            figure
            axis equal tight
            title(tit);
            hold on
            for i=1:size(c1,1)
                adj = cell2mat(h(i)); % Index of layer 1 intralayer adjacents
                x=c1(i,1);
                y=c1(i,2);
                quiver(repmat(x,size(adj,1),1), repmat(y,size(adj,1),1), adj(:,2).*adj(:,3), adj(:,2).*adj(:,4),0.3+inter*2);
            end
            scatter(c2(:,1), c2(:,2),36, 'red');
            if inter
                scatter(c1(:,1), c1(:,2),24, 'blue');
            end
            hold off
        end
    end
    
end
